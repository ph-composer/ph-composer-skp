/* The Schedule subtab: one row per run as the last schedule read found it, with totals by type and by group.
   Grouping, ordering and the text filter are view state and never change the Model. Locate selects a run's
   Edges, or a finding's, and opens the context holding them. The read is the owner's (shared.ScheduleRead):
   this view shows it, says when the Model has changed since, and offers Refresh. */
PhComposerUI.define("features/thermal_bridges/schedule", ["request", "workspace", "table", "view_controls",
  "fields", "units", "unit_preferences", "features/thermal_bridges/shared"],
function (request, ui, tables, viewControls, fields, units, preferences, shared) {
  "use strict";
  var LOCATE = shared.PREFIX + "runs.locate";
  var PSI = fields.LINEAR_PSI, LENGTH = fields.LENGTH_M, HEAT = fields.HEAT_LOSS;
  var QUANTITIES = { length_m: LENGTH, psi_w_mk: PSI, heat_loss_w_k: HEAT };
  var COLUMNS = [["display_name", "Thermal bridge"], ["zone", "Zone"], ["building_segment", "Building-Segment"],
    ["type_name", "Type"], ["group", "Group"], ["length_m", "Length"], ["psi_w_mk", "ψ-value"],
    ["quantity", "Quantity"], ["heat_loss_w_k", "Heat loss"]];

  function number(value, descriptor) {
    return value === null || value === undefined ? "—" : units.format(value, descriptor,
      units.profile(descriptor, preferences.current()), { showUnit: false });
  }
  function header(label, field) {
    return QUANTITIES[field] ? units.header(label, QUANTITIES[field], preferences.current()) : label;
  }
  function field(run, name) {
    if (name === "order") return run.order;
    if (name === "zone") return run.zone.name;
    if (name === "building_segment") return run.zone.building_segment;
    if (name === "type_name") return run.type_name;
    return run[name];
  }

  function Schedule(root, session, send, read, refresh) {
    var self = this;
    this.read = read; this.runs = []; this.expanded = Object.create(null);
    this.locate = request.channel(session, send, "thermal-bridge-locate", "view.invoke");
    this.controls = new viewControls.ViewControls({ label: "thermal bridges", placeholder: "Name, Zone or type",
      fields: [["order", "Schedule order"]].concat(COLUMNS), initialOrder: "order",
      groups: [["zone", "Zone"], ["type_name", "Type"], ["group", "Group"], ["building_segment", "Building-Segment"]],
      count: function (shown, total, narrowed) {
        return narrowed ? shown + " of " + total + " runs" : total + (total === 1 ? " run" : " runs");
      } }, function () { self.paint(); });
    this.status = ui.element("span", "tb-schedule-status");
    this.status.setAttribute("role", "status");
    this.refresh = ui.button("Refresh", function () { refresh(); });
    this.refresh.setAttribute("aria-label", "Refresh the schedule");
    this.controls.root.appendChild(this.status);
    this.controls.root.appendChild(this.refresh);
    root.appendChild(this.controls.root);
    this.mount = ui.element("div", "tb-schedule-table");
    // A click on a run's row selects its Edges; its controls (Locate, the findings glyph) keep their own clicks,
    // and the Locate icon is the keyboard route.
    this.mount.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || !target.closest || target.closest("button, input, select, a, .col-actions")) return;
      var row = target.closest("[data-row-key]"), key = row && row.getAttribute("data-row-key");
      var run = self.runs.filter(function (entry) { return entry.identifier === key; })[0];
      if (run) self.sendLocate(run.edge_paths);
    });
    root.appendChild(this.mount);
    this.totals = ui.element("div", "tb-schedule-totals");
    this.byType = ui.element("div", "tb-totals-table");
    this.byGroup = ui.element("div", "tb-totals-table");
    this.totals.appendChild(ui.element("h2", "", "Totals"));
    this.totals.appendChild(this.byType); this.totals.appendChild(this.byGroup);
    root.appendChild(this.totals);
    this.others = ui.element("div", "tb-schedule-others");
    root.appendChild(this.others);
    this.bubbles = Object.create(null);
    this.layer = ui.element("div", "tb-findings-layer");
    root.appendChild(this.layer);
  }
  Schedule.prototype.guard = function () { return this.locate.busy() ? "Wait for Locate to finish." : null; };
  Schedule.prototype.sendLocate = function (paths) {
    if (this.disposed || this.locate.busy()) return;
    this.locate.run(LOCATE, { edge_paths: JSON.parse(JSON.stringify(paths)) });
    this.paint();
  };
  /* `shown` is whether the Schedule is on screen: a hidden one only settles Locate and repaints when shown, so
     a long schedule costs nothing while the user works elsewhere. */
  Schedule.prototype.render = function (state, shown) {
    if (this.disposed) return;
    this.locate.consume(state);
    this.state = state;
    if (!shown) return;
    var value = this.read.value();
    if (value !== this.painted) {
      this.painted = value;
      this.runs = value ? value.runs.map(function (run, index) { return Object.assign({ order: index }, run); }) :
        [];
      this.pruneBubbles();
    }
    this.paint();
  };
  Schedule.prototype.paint = function () {
    if (this.disposed || !this.state) return;
    var self = this, value = this.read.value(), state = this.state;
    this.status.textContent = this.read.busy() ? "Reading the Model..." : this.read.error ||
      (this.read.stale(state) ? "The Model has changed since this was read." : "");
    this.status.classList.toggle("tb-schedule-error", Boolean(this.read.error) && !this.read.busy());
    this.refresh.disabled = this.read.busy();
    // One Building-Segment never shows the field.
    var segments = this.runs.map(function (run) { return run.zone.building_segment; })
      .filter(function (segment, index, all) { return all.indexOf(segment) === index; });
    var hidden = { building_segment: segments.length <= 1 };
    this.controls.setFields([["order", "Schedule order"]].concat(COLUMNS.filter(function (column) {
      return !hidden[column[0]];
    })));
    // A field that went away with its column orders by the schedule again.
    if (!this.controls.orderBy.value) this.controls.orderBy.value = "order";
    var projected = this.controls.project(this.runs, { id: function (run) { return run.identifier; },
      value: field, search: function (run) { return [run.display_name, run.zone.name, run.type_name || ""].join(" "); },
      group: function (run, name) {
        if (name === "group") return { label: shared.groupLabel(run.group) };
        var raw = field(run, name);
        return { label: raw === null || raw === undefined ? "None" : String(raw) };
      }, tie: function (a, b) { return a.order - b.order; } });
    var rows = projected.records.map(function (run) {
      return { key: run.identifier, record: run, tier: "Run", depth: 0, parent: null };
    });
    tables.table(this.mount, this.runs, { rows: rows, expanded: this.expanded,
      columns: [["actions", "Actions"]].concat(COLUMNS.map(function (column) {
        return [column[0], header(column[1], column[0])];
      })),
      hiddenColumns: hidden, rowHidden: projected.hidden, group: projected.group,
      visibleCount: projected.visibleCount, toggleGroup: function (key) { self.controls.toggleGroup(key); },
      value: function (row, name) { return field(row.record, name); },
      cell: function (td, row, name) { return self.cell(td, row.record, name); },
      actions: function (row) {
        return [{ id: "locate", icon: "locate", label: "Locate " + row.record.display_name }];
      },
      action: function (row) { self.sendLocate(row.record.edge_paths); },
      actionsCell: function (td, row) { self.findingsCell(td, row.record); },
      disabled: this.locate.busy(),
      empty: value ? (this.runs.length ? "No thermal bridges match this view." :
        "No thermal bridges yet. Assign a Thermal Bridge Type to Edges inside a Zone.") :
        this.read.error || "Reading the schedule..." });
    this.paintTotals(value);
    this.paintOthers(value);
  };
  Schedule.prototype.cell = function (td, run, name) {
    if (QUANTITIES[name]) {
      var text = number(run[name], QUANTITIES[name]);
      td.textContent = text;
      ui.tooltip(td, text !== "—" ? "" : name === "heat_loss_w_k" ? "No ψ-value, so no heat loss" : "No ψ-value");
      return true;
    }
    if (name === "group") { td.textContent = shared.groupLabel(run.group); return true; }
    if (name === "type_name" && !run.type_name) {
      td.textContent = "Missing type"; ui.tooltip(td, "Choose a replacement type for these Edges"); return true;
    }
    return false;
  };
  /* A run's findings behind one alert glyph, each with what to do and a Locate for the Edges it names. The
     bubble mounts outside the table, so the table's scroller and its sticky cells never clip or cover it. */
  Schedule.prototype.findingsCell = function (td, run) {
    var self = this, findings = run.findings || [], bubble = this.bubbles[run.identifier];
    if (!findings.length) {
      if (td._findings) td._findings.hidden = true;
      if (bubble) bubble.close(false);
      return;
    }
    if (!bubble || td._findings !== bubble.trigger) {
      if (bubble) bubble.root.remove();
      var trigger = ui.iconButton("", "alert");
      trigger.classList.add("row-icon");
      bubble = this.bubbles[run.identifier] = new ui.Bubble(trigger, "Findings", { detachedTrigger: true });
      bubble.root.classList.add("tb-findings");
      this.layer.appendChild(bubble.root);
      if (td._findings) td._findings.remove();
      td._findings = trigger;
      td.appendChild(trigger);
    }
    var blocks = findings.some(function (finding) { return finding.blocks_export; });
    td._findings.hidden = false;
    ui.paintIconButton(bubble.trigger, findings.length + (findings.length === 1 ? " finding" : " findings") +
      " for " + run.display_name, "alert");
    bubble.trigger.classList.toggle("tb-blocks-export", blocks);
    // Rewritten only when the findings change, so a repaint keeps the focus inside an open bubble.
    var key = JSON.stringify(findings);
    if (bubble.findings === key) return;
    bubble.findings = key;
    bubble.content.replaceChildren.apply(bubble.content, findings.map(function (finding) {
      var line = ui.element("div", "tb-finding");
      line.appendChild(ui.element("p", finding.blocks_export ? "tb-finding-blocks" : "", finding.message));
      line.appendChild(ui.button("Locate", function () {
        bubble.close(false);
        self.sendLocate(finding.locate.edge_paths);
      }));
      return line;
    }));
  };
  /* Drops the bubbles of runs the last read no longer has. */
  Schedule.prototype.pruneBubbles = function () {
    var kept = Object.create(null);
    this.runs.forEach(function (run) { kept[run.identifier] = true; });
    Object.keys(this.bubbles).forEach(function (key) {
      if (kept[key]) return;
      this.bubbles[key].close(false);
      this.bubbles[key].root.remove();
      delete this.bubbles[key];
    }, this);
  };
  Schedule.prototype.paintTotals = function (value) {
    this.totals.hidden = !value || !value.runs.length;
    if (this.totals.hidden) return;
    var totals = value.totals;
    tables.table(this.byType, totals.by_type, { rows: totals.by_type.map(function (row) {
      return { key: row.type_id, record: row, tier: "Type", depth: 0, parent: null };
    }), columns: [["type_name", "Type"], ["group", "Group"], ["run_count", "Runs"],
      ["length_m", header("Length", "length_m")], ["heat_loss_w_k", header("Heat loss", "heat_loss_w_k")]],
    value: function (row, name) { return row.record[name]; }, cell: function (td, row, name) {
      if (name === "type_name") { td.textContent = row.record.type_name || "Missing type"; return true; }
      if (name === "group") { td.textContent = shared.groupLabel(row.record.group); return true; }
      if (!QUANTITIES[name]) return false;
      td.textContent = number(row.record[name], QUANTITIES[name]); return true;
    }, empty: "" });
    var groups = totals.by_group.concat([{ group: null, heat_loss_w_k: totals.heat_loss_w_k }]);
    tables.table(this.byGroup, groups, { rows: groups.map(function (row) {
      return { key: row.group || "all", record: row, tier: "Group", depth: 0, parent: null };
    }), columns: [["group", "Group"], ["heat_loss_w_k", header("Heat loss", "heat_loss_w_k")]],
    value: function (row, name) { return row.record[name]; }, cell: function (td, row, name) {
      if (name === "group") { td.textContent = row.record.group ? shared.groupLabel(row.record.group) : "All"; }
      else td.textContent = number(row.record.heat_loss_w_k, HEAT);
      return true;
    }, empty: "" });
  };
  /* Assigned Edges in no run and assignments that do not read: they belong to no row, so they collect here,
     each with a Locate. */
  Schedule.prototype.paintOthers = function (value) {
    var self = this, items = value ? value.edge_findings.concat(value.unreadable) : [];
    this.others.hidden = !items.length;
    if (!items.length) { this.others.replaceChildren(); return; }
    var count = value.edge_finding_total + value.unreadable_total;
    var list = ui.element("ul", "tb-other-findings");
    items.forEach(function (item) {
      var line = ui.element("li");
      line.appendChild(ui.element("span", "", item.message));
      line.appendChild(ui.button("Locate", function () { self.sendLocate([item.path]); }));
      list.appendChild(line);
    });
    this.others.replaceChildren(ui.element("h2", "", "Not in the schedule (" + count + ")"), list);
  };
  Schedule.prototype.dispose = function () { this.disposed = true; this.locate.reset(); };
  return { Schedule: Schedule };
});
