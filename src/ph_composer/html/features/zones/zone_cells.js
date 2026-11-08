/* Name and Ground depth retain the shared inline drafts. Segment and Level assignments are guarded
   stable-ID selects. Legacy/missing choices open explicit adoption instead of accepting category text.

   No refusal leaves the screen behind an invisible draft. A refused choice wrote nothing, so the select
   returns to the Model's value and keeps the reason as a diagnostic; nothing is held. A choice the Model
   then contradicts (it changed underneath, or it settled on another value) is held with a visible Cancel,
   and choosing again retries against the current values. A Zone that shares its identity or storage with
   another occurrence (`gated`) is read only: every write to it refuses until it is made independent. */
PhComposerUI.define("features/zones/zone_cells", ["record_edits", "fields", "units", "workspace", "request",
  "features/zones/zone_options"], function (RecordEdits, fields, units, ui, requests, options) {
  "use strict";
  var GROUND_DEPTH = fields.with(fields.LENGTH_MM, { label: "Ground depth", scope: "ph_composer.zones.ground_depth" });
  var COLUMNS = [["building_segment", "Building-Segment"], ["level", "Level"], ["ground_depth_mm", "Ground depth"]];
  var HELD = { differs: "The Model differs from this choice. Cancel, or choose again.",
    changed: "Changed in the Model. Cancel, or choose again." };
  // The resolver's text names the duplicated id; the user needs the route out. Codes stay the contract.
  var SHARED = {
    "target.ambiguous": "Another Zone carries this Zone's identity, as a copy does, so nothing was written. " +
      "Its cells stay read only until it is made independent.",
    "target.shared_definition": "This Zone shares its Faces with another occurrence, so an edit would reach " +
      "both. Nothing was written."
  };
  var UNCERTAIN = "The edit failed and may have been partly applied. The cell shows the Model's current value; " +
    "check it before editing again.";
  function copy(values) { return JSON.parse(JSON.stringify(values || {})); }
  function same(left, right) { return JSON.stringify(left) === JSON.stringify(right); }
  /* What a Zone write's outcome says to the user, or null when the host's message stands. */
  function refusalText(outcome) {
    if (!outcome || outcome.status === "completed") return null;
    if (outcome.effect === "unknown") return UNCERTAIN;
    return SHARED[outcome.code] || null;
  }
  function zoneSeen(row) { return [row.record.zone.state, row.record.zone.values]; }
  function gated(zone) { return Boolean(zone && GATED[zone.state]); }
  var GATED = { ambiguous: true, shared_definition: true, wrong_hierarchy: true };
  function ZoneCells(session, send, notice, manage, guard) {
    var self = this;
    this.manage = manage; this.guard = guard; this.notice = notice; this.cells = {}; this.statusSerial = 0;
    this.channel = requests.channel(session, function (type, payload) {
      send(type, Object.assign({}, payload, { expected_revision: self.revision }));
    }, "zone_assignment");
    this.edits = new RecordEdits(session, send, notice, {
      action: "ph_composer.zones.update", fields: ["name", "ground_depth_mm"],
      recordLabel: "Zone", requiredFields: ["name"], navigateOnCommit: false,
      quantities: { ground_depth_mm: GROUND_DEPTH },
      eligible: function (row, field) { return Boolean(row.record.zone) && this.fields.indexOf(field) >= 0; },
      rawValue: function (row, field) { return row.record.zone.values[field]; },
      readOnly: function (cell) {
        return Boolean(self.pending || self.guard && self.guard() || gated(cell.row.record.zone));
      },
      cancelControl: true, refusalText: refusalText,
      label: function (row, field) { return row.record.name + " " + (field === "name" ? "name" : "ground depth"); },
      send: function (cell) {
        var zone = cell.row.record.zone, values = copy(zone.values);
        values[cell.field] = cell.submitted;
        return { action: "ph_composer.zones.update", params: { reference: copy(zone.reference),
          values: values, expected_values: copy(zone.values) } };
      }
    });
  }
  ZoneCells.columns = function (profile) {
    return COLUMNS.map(function (column) {
      return column[0] === "ground_depth_mm" ? [column[0], units.header(column[1], GROUND_DEPTH, profile)] : column;
    });
  };
  ZoneCells.GROUND_DEPTH = GROUND_DEPTH;
  ZoneCells.refusalText = refusalText;
  ZoneCells.gated = gated;
  ZoneCells.prototype.refresh = function (rows, state) {
    this.revision = state.revision; this.options = options.read(state);
    this.edits.refresh(rows, state);
    var self = this, outcome = this.channel.consume(state), live = {};
    rows.forEach(function (row) { live[row.key] = row; });
    Object.keys(this.cells).forEach(function (key) {
      var cell = self.cells[key], row = live[cell.row.key];
      if (!row) { if (self.pending === cell) self.pending = null; delete self.cells[key]; return; }
      cell.row = row;
      if (self.pending === cell && outcome) {
        self.pending = null;
        if (outcome.status !== "completed") {
          // Nothing was held: the select shows the Model's value again and keeps the reason.
          cell.draft = undefined; cell.held = false;
          cell.error = refusalText(outcome) || outcome.message || "The assignment was not applied.";
        } else if (options.value(row.record.zone, cell.field) !== cell.draft) {
          cell.held = true; cell.error = HELD.differs;
        } else { cell.draft = undefined; cell.held = false; cell.error = ""; }
      } else if (cell.held && !self.pending && !same(cell.expected, row.record.zone.values)) {
        if (cell.error !== HELD.changed) cell.error = HELD.changed;
      } else if (!cell.held && self.pending !== cell && cell.error && !same(cell.seen, zoneSeen(row))) {
        // A diagnostic describes the Zone it was refused against; once the Zone has changed it is stale.
        cell.error = "";
      }
      cell.seen = zoneSeen(row);
    });
  };
  ZoneCells.prototype.active = function () {
    return Boolean(this.pending) || Object.keys(this.cells).some(function (key) {
      return this.cells[key].held;
    }, this) || Object.keys(this.edits.cells).some(function (key) { return this.edits.cells[key].status !== "clean";
      }, this);
  };
  ZoneCells.prototype.render = function (td, row, field) {
    if (field !== "building_segment" && field !== "level") return this.edits.render(td, row, field);
    if (!row.record.zone) return false;
    var self = this, zone = row.record.zone, id = options.value(zone, field);
    var key = row.key + ":" + field, cell = this.cells[key];
    var requiresAdoption = !options.managed(zone) || (id && !options.find(this.options, field, id));
    td.classList.add("phc-pill-cell");
    // A held choice stays visible with its Cancel even when the Zone becomes read only underneath it.
    if (gated(zone) && !(cell && (cell.held || this.pending === cell))) {
      var pill = td._zonePill;
      if (!pill) pill = td._zonePill = ui.element("span", "phc-enum-pill");
      pill.textContent = options.label(this.options, zone, field);
      options.paint(pill, options.colour(this.options, zone, field));
      ui.tooltip(td, "Read only while this Zone is shared with another occurrence.");
      td.classList.remove("has-cell-error", "phc-editable-cell");
      if (pill.parentNode !== td) td.replaceChildren(pill); return true;
    }
    ui.tooltip(td, "");
    // An editable choice owns its error and Cancel inside the cell, so the row never grows for them.
    td.classList.toggle("phc-editable-cell", !requiresAdoption);
    if (requiresAdoption) {
      var adopt = td._zoneAdopt;
      if (!adopt) adopt = td._zoneAdopt = ui.button("", function () { self.manage(field); });
      adopt.textContent = options.label(this.options, zone, field);
      adopt.className = "phc-enum-pill phc-zone-adoption";
      adopt.setAttribute("aria-label", row.record.name + " " + (field === "level" ? "Level" : "Building-Segment"));
      ui.tooltip(adopt, "Read only. Adopt managed options to assign " + options.title(field) + ".");
      options.paint(adopt, options.colour(this.options, zone, field));
      if (adopt.parentNode !== td) td.replaceChildren(adopt); return true;
    }
    if (!cell) {
      cell = this.cells[key] = { row: row, field: field, input: ui.element("select", "phc-enum-cell phc-cell-input"),
        status: ui.element("small", "cell-error"), error: "", held: false };
      cell.cancel = ui.iconButton("Cancel choice", "clear", function () { self.cancel(cell); });
      cell.cancel.classList.add("phc-cell-cancel");
      cell.status.id = "zone-choice-" + (++this.statusSerial) + "-" + this.channel.session;
      cell.status.setAttribute("role", "alert"); cell.input.setAttribute("aria-describedby", cell.status.id);
      cell.input.addEventListener("change", function () { self.assign(cell); });
      cell.input.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && self.pending !== cell && (cell.held || cell.error)) {
          event.preventDefault(); self.cancel(cell);
        }
      });
    }
    cell.row = row;
    var signature = JSON.stringify(options.list(this.options, field).map(function (choice) { return [choice.id,
      choice.values.name]; }));
    if (signature !== cell.signature) {
      cell.input.replaceChildren();
      if (field === "level") cell.input.appendChild(ui.option("", "Not set"));
      options.list(this.options, field).forEach(function (choice) { cell.input.appendChild(ui.option(choice.id,
        choice.values.name)); });
      cell.signature = signature;
    }
    cell.input.setAttribute("aria-label", row.record.name + " " + (field === "level" ? "Level" : "Building-Segment"));
    ui.paintIconButton(cell.cancel, "Cancel " + cell.input.getAttribute("aria-label") + " choice", "clear");
    cell.input.disabled = this.channel.busy() || Boolean(this.guard && this.guard()) || gated(zone);
    cell.input.setAttribute("aria-busy", String(this.pending === cell));
    cell.td = td;
    this.paintState(cell);
    if (cell.input.parentNode !== td) td.replaceChildren(cell.input, cell.cancel, cell.status);
    return true;
  };
  /* The parts of a choice cell that follow its draft and error, without rebuilding its options. */
  ZoneCells.prototype.paintState = function (cell) {
    var zone = cell.row.record.zone;
    cell.input.value = cell.draft === undefined ? options.value(zone, cell.field) || "" : cell.draft || "";
    cell.input.setAttribute("aria-invalid", String(Boolean(cell.error)));
    cell.status.textContent = cell.error; cell.status.hidden = !cell.error;
    cell.cancel.hidden = !cell.held || this.pending === cell;
    var selected = options.find(this.options, cell.field, cell.input.value);
    options.paint(cell.input, selected && selected.values.colour);
    if (cell.td) {
      cell.td.classList.toggle("has-cell-error", Boolean(cell.error));
      if (cell.error) ui.placeCellError(cell.td);
    }
  };
  /* Drops a held choice or a diagnostic and shows the Model's value. A sent request is not retracted. */
  ZoneCells.prototype.cancel = function (cell) {
    if (this.pending === cell) return;
    cell.draft = undefined; cell.held = false; cell.error = "";
    this.paintState(cell);
  };
  /* Whether a request id is one of this screen's Zone writes still waiting for its outcome. */
  ZoneCells.prototype.owns = function (id) {
    var typed = this.edits.pending;
    return Boolean(id) && (id === this.channel.pending || Boolean(typed && typed.request === id));
  };
  /* Cancels every held Zone edit, choices and typed drafts alike: the guard notice's Cancel. */
  ZoneCells.prototype.cancelAll = function () {
    Object.keys(this.cells).forEach(function (key) { this.cancel(this.cells[key]); }, this);
    this.edits.cancelAll();
  };
  /* A new choice clears a diagnostic and, for a held choice, retries against the Model's current values.
     Choosing the Model's own value cancels a held choice without a request. */
  ZoneCells.prototype.assign = function (cell) {
    var zone = cell.row.record.zone, id = cell.input.value || null;
    if (this.channel.busy() || this.guard && this.guard() || gated(zone)) { this.paintState(cell); return; }
    if (id === options.value(zone, cell.field)) { this.cancel(cell); return; }
    cell.expected = copy(zone.values); cell.draft = id; cell.held = false; cell.error = "";
    var values = copy(zone.values); values[cell.field + "_id"] = id;
    this.pending = cell;
    this.channel.run("ph_composer.zones.update", { reference: copy(zone.reference), values: values,
      expected_values: cell.expected });
    this.paintState(cell);
    cell.input.disabled = true; cell.input.setAttribute("aria-busy", "true");
  };
  ZoneCells.prototype.dispose = function () { this.channel.reset(); this.edits.dispose(); this.cells = {}; };
  return ZoneCells;
});
