/* Zones owns Assembly assignment, its selection review, and the usage it contributes to other tables. */
PhComposerUI.define("features/zones/assembly_assignment", ["panel", "snapshot", "request", "workspace", "units",
  "fields", "inventory_forms", "face_words"], function (panel, snapshot, requests, ui, units, fields, forms, words) {
  "use strict";
  var PREFIX = "ph_composer.zones.faces", TABLE = "ph_composer.assemblies.assemblies";
  var FACES_NAMED = 20;
  var usageView = null, replacement = null, contributionSession = null;
  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function choices(state, types) {
    var records = (snapshot.value(state, PREFIX + ".assemblies") || {}).assemblies || [];
    return records.slice().sort(function (a, b) {
      var matchA = Boolean(a.type && types.indexOf(a.type) >= 0);
      var matchB = Boolean(b.type && types.indexOf(b.type) >= 0);
      return Number(matchB) - Number(matchA) || ui.compareText(a.name, b.name) || ui.compareText(a.id, b.id);
    });
  }
  function options(select, records, firstLabel, clear) {
    select.replaceChildren(ui.option("", firstLabel));
    if (clear) select.appendChild(ui.option("__clear__", "Clear Assembly"));
    records.forEach(function (record) { select.appendChild(ui.option(record.id, record.name)); });
  }
  /* The Assembly for a set of Faces: those selected in the viewport, or those `targets()` answers (the
     Faces view's checked set). It rests on the Assembly they all share, reads "Mixed" when they differ and
     "Choose Assembly" when none has one. Choosing one assigns it at once, as one Undo step, to the targets
     named when the choice was made; a refusal says why and returns the control to its resting value. A Face
     with no record yet cannot hold an Assembly, so the control waits, and says so, while one is among them. */
  function Picker(session, send, guard, refused, targets) {
    var self = this;
    this.session = session;
    this.guard = guard;
    this.refused = refused || function (reason) { panel.notify(reason, "warning"); };
    this.requests = requests.channel(session, send, "selected-assembly");
    this.root = ui.element("div", "phc-selection-assembly");
    this.select = ui.element("select");
    this.select.setAttribute("aria-label", "Assembly for selected Faces");
    this.error = ui.element("span", "cell-error");
    this.error.setAttribute("role", "status");
    this.root.appendChild(this.select);
    this.root.appendChild(this.error);
    this.currentTargets = [];
    this.targetsFrom = targets || null;
    this.overLimit = false;
    this.resting = "";
    this.select.addEventListener("change", function () {
      var chosen = self.select.value, reason;
      if (self.disposed || !self.enabled || self.requests.busy()) return;
      // The first option is a label, not a choice: the control goes back to what the Faces hold.
      if (!chosen || chosen === self.resting) { self.select.value = self.resting; return; }
      reason = self.guard && self.guard();
      if (reason) { self.select.value = self.resting; self.refused(reason); return; }
      self.submit(chosen);
    });
  }
  Picker.prototype.active = function () { return this.requests.busy(); };
  Picker.prototype.paint = function () {
    var unclassified = this.currentTargets.some(function (target) { return !target.expected_values.face_type; });
    this.root.hidden = !this.enabled || !this.currentTargets.length;
    this.select.disabled = this.disposed || !this.enabled || this.requests.busy() || !this.currentTargets.length ||
      unclassified || this.overLimit;
    ui.tooltip(this.select, unclassified ? "Classify every checked Face before choosing its Assembly" : "");
  };
  /* Disables the control while the set is larger than one assignment may change; the owner says why. */
  Picker.prototype.limit = function (over) {
    if (this.overLimit === Boolean(over)) return;
    this.overLimit = Boolean(over);
    this.paint();
  };
  Picker.prototype.submit = function (chosen) {
    var self = this;
    if (!this.currentTargets.length) return;
    this.error.textContent = "";
    this.requests.run(PREFIX + ".assign_assembly", { targets: clone(this.currentTargets),
      assembly_id: chosen === "__clear__" ? null : chosen }, {
      onDone: function () { self.select.value = self.resting; },
      onFail: function (outcome) {
        self.select.value = self.resting;
        self.error.textContent = snapshot.message(outcome, "The Assembly was not assigned. Nothing was written.");
      }
    });
    this.paint();
  };
  Picker.prototype.refresh = function (state) {
    if (this.disposed) return;
    this.state = state;
    var selection = snapshot.value(state, PREFIX + ".selected");
    this.enabled = Boolean((this.targetsFrom || snapshot.section(state, PREFIX + ".selected")) &&
      snapshot.value(state, PREFIX + ".assemblies") && snapshot.value(state, PREFIX + ".faces"));
    this.currentTargets = this.targetsFrom ? this.targetsFrom() : selection ? selection.targets || [] : [];
    if (!this.enabled) { this.requests.reset(); this.select.value = ""; this.error.textContent = ""; }
    else this.requests.consume(state);
    var records = choices(state, this.currentTargets.map(function (target) {
      return target.expected_values.face_type;
    }));
    var selected = this.select.value;
    var held = this.currentTargets.map(function (target) { return target.expected_values.assembly_id || ""; });
    var shared = held.every(function (id) { return id === held[0]; }) ? held[0] || "" : null;
    var first = shared === null ? "Mixed" : "Choose Assembly";
    var signature = first + "|" + records.map(function (record) { return record.id + ":" + record.name; }).join("|");
    // Rebuilt only when the choices change: a snapshot follows every viewport click.
    if (this.signature !== signature) {
      options(this.select, records, first, true);
      this.signature = signature;
    }
    this.resting = shared && records.some(function (record) { return record.id === shared; }) ? shared : "";
    // A choice in flight stays shown until its outcome arrives.
    this.select.value = this.requests.busy() ? selected : this.resting;
    this.paint();
  };
  Picker.prototype.dispose = function () {
    this.disposed = true; this.enabled = false;
    this.requests.reset(); this.paint();
  };
  /* An assigned chip takes its Assembly's colour, the swatch the Assemblies table shows; None and a
     missing Assembly keep the neutral pill. */
  function paintColor(chip, record) { ui.paintChip(chip, record && record.color); }
  function cell(td, row, state, guard, refused) {
    var face = row.record.face;
    if (!face) return false;
    var records = choices(state.snapshot, [face.values.face_type]);
    var chip = td._assemblyChip;
    if (!chip || td._assemblySession !== state.session) {
      var ownerSession = state.session;
      var reject = refused || function (reason) { panel.notify(reason, "warning"); };
      td._assemblySession = ownerSession;
      chip = td._assemblyChip = ui.element("select", "phc-cell-input phc-enum-cell");
      chip.addEventListener("change", function () {
        var live = td._assemblyState;
        if (!live || live.session !== ownerSession || live.disposed || !chip.isConnected ||
            !live.assemblyEnabled || live.edits.busy()) return;
        var reason = guard(live);
        if (reason) { reject(reason); chip.value = td._assemblyFace.values.assembly_id || ""; return; }
        live.edits.run(PREFIX + ".assign_assembly", { targets: [{ reference: clone(td._assemblyFace.reference),
          expected_values: clone(td._assemblyFace.values) }], assembly_id: chip.value || null });
      });
      td.className = "col-assembly_id phc-editable-cell";
      td.replaceChildren(chip);
    }
    var chosen = face.values.assembly_id;
    options(chip, records, "None", false);
    if (chosen && !records.some(function (record) { return record.id === chosen; })) {
      chip.appendChild(ui.option(chosen, "Missing Assembly · " + chosen));
    }
    chip.value = chosen || "";
    paintColor(chip, records.filter(function (record) { return record.id === chosen; })[0]);
    chip.setAttribute("aria-label", row.record.name + " Assembly");
    chip.setAttribute("aria-invalid", String(face.assembly_state === "dangling" || face.assembly_state === "invalid"));
    chip.disabled = state.disposed || !state.assemblyEnabled || state.edits.busy();
    td._assemblyState = state;
    td._assemblyFace = face;
    return true;
  }
  function usage(state, id) {
    var rows = (snapshot.value(state, PREFIX + ".usage") || {}).assembly_usage || [];
    return rows.filter(function (row) { return row.assembly_id === id; })[0] ||
      { face_count: 0, gross_area_m2: 0, faces: [] };
  }
  /* The Faces an Assembly is on, called what the Faces view calls them: a long list names its first and counts the
     rest. */
  function useNames(state, id) {
    var wanted = usage(state, id), read = (snapshot.value(state, PREFIX + ".usage") || {}).faces || [];
    var byReference = Object.create(null), byZone = Object.create(null);
    read.forEach(function (face) {
      var zone = JSON.stringify(face.reference.zone_path);
      byReference[JSON.stringify(face.reference)] = face;
      (byZone[zone] = byZone[zone] || []).push(face);
    });
    var names = wanted.faces.slice(0, FACES_NAMED).map(function (reference) {
      var face = byReference[JSON.stringify(reference)];
      return face ? face.zone_name + " · " + words.faceName(face, byZone[JSON.stringify(reference.zone_path)]) : "Face";
    });
    var more = wanted.face_count - names.length;
    return { count: wanted.face_count, description: wanted.face_count +
      (wanted.face_count === 1 ? " Face: " : " Faces: ") + names.join(", ") +
      (more > 0 ? ", and " + more + " more" : "") };
  }
  /* The Assembly the paint tool is on, or null when it is off or painting something else. */
  function painting(state) {
    var tool = snapshot.value(state, PREFIX + ".palette") || {};
    return tool.active && tool.palette && tool.palette.assembly_id || null;
  }
  /* Whether the Assemblies table is what shows the paint tool at the moment: its row says which Assembly. */
  function paintShown(state) {
    return Boolean(state.ui && state.ui.activeTab === "assemblies" && painting(state));
  }
  function settleContributions(state) {
    var available = Boolean(snapshot.value(state, PREFIX + ".usage"));
    if (contributionSession !== state.session || !available) {
      if (usageView) usageView.reset();
      if (replacement) {
        replacement.dispose();
        if (replacement.root.parentNode) replacement.root.parentNode.removeChild(replacement.root);
      }
      replacement = null; usageView = null; contributionSession = state.session;
    }
    if (usageView) usageView.consume(state);
    if (replacement) replacement.refresh(state);
    return available;
  }
  ui.contributeTable(TABLE, { id: PREFIX + ".assembly_usage", available: settleContributions,
    columns: [["face_usage", "Faces · Gross area"]],
    value: function (row, _field, state) { return usage(state, row.record.id); },
    cell: function (td, _row, _field, value) {
      td.textContent = value.face_count + " · " + units.format(value.gross_area_m2, fields.AREA_M2,
        units.profile(fields.AREA_M2));
      td.setAttribute("aria-label", value.face_count + " Faces · gross area");
      return true;
    }, actions: function (row, state) {
      var count = usage(state, row.record.id).face_count, name = row.record.values.name;
      var pressed = painting(state) === row.record.id;
      var others = ((snapshot.value(state, TABLE) || {}).records || []).some(function (candidate) {
        return candidate.id !== row.record.id;
      });
      // These act on Faces in the Model, not on the Assembly record, so they start their own group.
      return [{ id: "select_assembly_faces", icon: "locate", disabled: !count, starts: true,
        label: "Select faces using " + name },
      { id: "paint_assembly", icon: "paint_bucket", pressed: pressed,
        label: pressed ? "Stop painting " + name : "Paint " + name + " onto faces" },
      { id: "replace_assembly", icon: "replace", disabled: !count, label: "Replace and delete " + name,
        unavailable: others ? null : name + " is the only Assembly, so there is nothing to replace it with." }];
    }, action: function (row, action, control, state, send) {
      var live = panel.state || state;
      if (live.session !== state.session || !snapshot.value(live, TABLE) || !snapshot.value(live, PREFIX + ".usage") ||
          (control && !control.isConnected)) return;
      var id = row.record.id;
      if (action.id === "replace_assembly") {
        if (replacement && !replacement.root.hidden) return;
        if (!replacement) {
          replacement = new forms.ReplacementForm(state.session, send, function () { panel.repaint(); },
            { section: TABLE, label: "Assembly", replacement: true, allowClear: true, usedOn: "Face",
              usage: useNames });
          document.body.appendChild(replacement.root);
        }
        replacement.refresh(live);
        var records = (snapshot.value(live, TABLE) || {}).records || [];
        var record = records.filter(function (candidate) { return candidate.id === id; })[0];
        if (record) replacement.open(record, records);
        return;
      }
      if (usageView && usageView.busy()) return;
      if (!usageView) usageView = requests.channel(state.session, send, "assembly-usage", "view.invoke");
      if (action.id === "select_assembly_faces") {
        // The Faces are checked in the Zones tab's Faces view, ready for a bulk assignment, and framed there, so the
        // outline is that screen's to clear; SketchUp's selection is left alone.
        var references = usage(live, id).faces;
        if (references.length) {
          panel.navigate("overview", { view: "ph_composer.zones.faces", check: clone(references), locate: true });
        }
      } else if (action.id === "paint_assembly") {
        // Painting happens in the viewport and the row shows it, so the panel stays where the tool was started.
        if (painting(live) === id) usageView.run(PREFIX + ".stop_classifying", {});
        else usageView.run(PREFIX + ".choose", { field: "assembly_id", value: id, reset: true });
      }
    }
  });
  panel.navigationGuard(PREFIX + ".replace_assembly", function () {
    return replacement && !replacement.root.hidden ? "Finish the Assembly replacement first." : null;
  }, panel.notify);
  return { Picker: Picker, cell: cell, choices: choices, options: options, usage: usage, paintShown: paintShown };
});
