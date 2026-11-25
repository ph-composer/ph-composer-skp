/* The piping schedule on the Piping pill: one row per run as the last read found it, grouped by Hot Water System,
   each trunk followed by its branches and each branch by its twigs, indented beneath it; then totals by role and by
   System. Grouping, ordering and the text filter are view state. A row click selects the run's pipes (runs.locate)
   and opens the group holding them; findings sit behind an alert glyph, each with its own Locate. The read is the
   owner's (shared.Read): this view shows it, says when the Model has changed since, and offers Refresh. */
PhComposerUI.define("features/piping/schedule", ["request", "workspace", "table", "view_controls", "fields", "units",
  "unit_preferences", "features/piping/shared", "sections/colour_by"],
function (request, ui, tables, viewControls, fields, units, preferences, shared, colourBy) {
  "use strict";
  var LENGTH = fields.LENGTH_M, TEMPERATURE = fields.TEMPERATURE_C, HOURS = fields.HOURS_PER_DAY;
  var COLUMNS = [["display_name", "Run"], ["system", "Hot Water System"], ["group", "Piping group"],
    ["role", "Role"], ["parent_name", "Parent"], ["pipe_type_name", "Pipe Type"], ["length_m", "Length"],
    ["line_count", "Lines"], ["values", "Role values"]];
  var WIDTHS = { display_name: 150, system: 140, group: 130, role: 110, parent_name: 120, pipe_type_name: 120,
    length_m: 100, line_count: 70, values: 150 };

  function number(value, descriptor, showUnit) {
    return value === null || value === undefined ? "—" : units.format(value, descriptor,
      units.profile(descriptor, preferences.current()), { showUnit: Boolean(showUnit) });
  }
  function header(label, descriptor) { return units.header(label, descriptor, preferences.current()); }
  /* A trunk's multiplier and demand recirculation, or a recirculation run's temperature and hours. */
  function roleValues(run) {
    var values = run.values || {};
    if (run.role === "trunk") {
      return "× " + values.multiplier + (values.demand_recirculation ? " · demand recirculation" : "");
    }
    if (run.role === "recirculation") {
      return number(values.water_temp_c, TEMPERATURE, true) + " · " + number(values.daily_period, HOURS, true);
    }
    return "";
  }
  function field(run, name) {
    if (name === "system") return run.hot_water_system_name || "No Hot Water System";
    if (name === "group") return run.group.name || "Piping group";
    if (name === "role") return shared.roleLabel(run.role);
    if (name === "values") return roleValues(run);
    return run[name];
  }
  /* The runs in schedule order with each trunk's branches and each branch's twigs moved beneath it, with depth. */
  function treeOrder(runs) {
    var children = Object.create(null), placed = Object.create(null), ordered = [];
    runs.forEach(function (run) { if (run.parent) (children[run.parent] = children[run.parent] || []).push(run); });
    function place(run, depth) {
      if (placed[run.identifier]) return;
      placed[run.identifier] = true;
      ordered.push(Object.assign({ order: ordered.length, depth: depth }, run));
      (children[run.identifier] || []).forEach(function (child) { place(child, depth + 1); });
    }
    runs.forEach(function (run) { if (!run.parent) place(run, 0); });
    runs.forEach(function (run) { place(run, 0); });
    return ordered;
  }

  function Schedule(root, session, send, read, refresh) {
    var self = this;
    this.read = read; this.runs = [];
    this.locate = request.channel(session, send, "piping-locate", "view.invoke");
    this.toggles = new colourBy.HeaderToggles({ role: shared.BY_ROLE, pipe_type_name: shared.BY_TYPE });
    this.controls = new viewControls.ViewControls({ label: "piping runs", placeholder: "Run, System or Pipe Type",
      fields: [["order", "Schedule order"]].concat(COLUMNS), initialOrder: "order",
      groups: [["system", "Hot Water System"], ["group", "Piping group"], ["role", "Role"],
        ["pipe_type_name", "Pipe Type"]],
      count: function (shown, total, narrowed) {
        return narrowed ? shown + " of " + total + " runs" : total + (total === 1 ? " run" : " runs");
      } }, function () { self.paint(); });
    this.controls.groupBy.value = "system";
    this.status = ui.element("span", "piping-status");
    this.status.setAttribute("role", "status");
    this.refresh = ui.button("Refresh", function () { refresh(); });
    this.refresh.setAttribute("aria-label", "Refresh the schedule and the Piping groups");
    this.controls.root.appendChild(this.refresh);
    this.controls.root.appendChild(this.status);
    root.appendChild(ui.element("h2", "piping-schedule-title", "Schedule"));
    root.appendChild(this.controls.root);
    this.mount = ui.element("div", "piping-table piping-schedule");
    this.mount.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || !target.closest || target.closest("button, input, select, a, .col-actions")) return;
      var row = target.closest("[data-row-key]"), key = row && row.getAttribute("data-row-key");
      var run = self.runs.filter(function (entry) { return entry.identifier === key; })[0];
      if (run) self.sendLocate(run.edge_paths);
    });
    root.appendChild(this.mount);
    this.totals = ui.element("div", "piping-totals");
    this.byRole = ui.element("div", "piping-table");
    this.bySystem = ui.element("div", "piping-table");
    [ui.element("h2", "", "Totals"), ui.element("h3", "", "By role"), this.byRole,
      ui.element("h3", "", "By Hot Water System"), this.bySystem].forEach(function (node) {
      self.totals.appendChild(node);
    });
    root.appendChild(this.totals);
    this.others = ui.element("div", "piping-others");
    root.appendChild(this.others);
    this.bubbles = Object.create(null);
    this.layer = ui.element("div", "piping-findings-layer");
    root.appendChild(this.layer);
  }
  Schedule.prototype.guard = function () { return this.locate.busy() ? "Wait for Locate to finish." : null; };
  /* Locate is an Undo step of its own and so a new revision, but changes no data: a current read stays current. */
  Schedule.prototype.sendLocate = function (paths) {
    if (this.disposed || this.locate.busy()) return;
    var read = this.read, current = this.state && !read.stale(this.state);
    this.locate.run(shared.PREFIX + "runs.locate", { edge_paths: JSON.parse(JSON.stringify(paths)) }, {
      onDone: function () { if (current) read.carryForward = true; } });
    this.paint();
  };
  Schedule.prototype.render = function (state, shown) {
    if (this.disposed) return;
    this.locate.consume(state);
    if (this.read.carryForward && this.read.result && this.read.result.revision !== state.revision) {
      this.read.result.revision = state.revision;
      this.read.carryForward = false;
    }
    this.state = state;
    if (!shown) return;
    var value = this.read.value();
    if (value !== this.painted) {
      this.painted = value;
      this.runs = value ? treeOrder(value.runs) : [];
      this.pruneBubbles();
    }
    this.paint();
  };
  Schedule.prototype.paint = function () {
    if (this.disposed || !this.state) return;
    var self = this, value = this.read.value(), state = this.state;
    this.status.textContent = this.read.busy() ? "Reading the Model..." : this.read.error ||
      (this.read.stale(state) ? "Changed since read" : "");
    this.status.classList.toggle("piping-error", Boolean(this.read.error) && !this.read.busy());
    this.refresh.disabled = this.read.busy();
    var projected = this.controls.project(this.runs, { id: function (run) { return run.identifier; },
      value: field, search: function (run) {
        return [run.display_name, field(run, "system"), run.pipe_type_name || ""].join(" ");
      }, group: function (run, name) { return { label: String(field(run, name) || "None") }; },
      tie: function (a, b) { return a.order - b.order; } });
    var rows = projected.records.map(function (run) {
      return { key: run.identifier, record: run, tier: "Run", depth: 0, parent: null };
    });
    tables.table(this.mount, this.runs, { rows: rows, defaultWidths: WIDTHS,
      columns: [["actions", "Actions"]].concat(COLUMNS.map(function (column) {
        return [column[0], column[0] === "length_m" ? header(column[1], LENGTH) : column[1]];
      })),
      headerActions: function (name) { return self.toggles.actions(state, name); },
      rowHidden: projected.hidden, group: projected.group, visibleCount: projected.visibleCount,
      toggleGroup: function (key) { self.controls.toggleGroup(key); },
      value: function (row, name) { return field(row.record, name); },
      cell: function (td, row, name) { return self.cell(td, row.record, name); },
      actions: function (row) {
        return [{ id: "locate", icon: "locate", label: "Locate " + row.record.display_name }];
      },
      action: function (row) { self.sendLocate(row.record.edge_paths); },
      actionsCell: function (td, row) { self.findingsCell(td, row.record); },
      disabled: this.locate.busy(),
      empty: value ? (this.runs.length ? "No runs match this view." :
        "No pipes yet. Draw lines in a Piping group and assign them a Pipe Type and a role.") :
        this.read.error || "Reading the schedule..." });
    this.paintTotals(value);
    this.paintOthers(value);
  };
  Schedule.prototype.cell = function (td, run, name) {
    if (name === "display_name") {
      td.textContent = run.display_name;
      // A branch sits under its trunk and a twig under its branch while the rows keep the schedule's order.
      var tree = this.controls.orderBy.value === "order" && ["", "system", "group"].indexOf(
        this.controls.groupBy.value) >= 0;
      td.style.paddingLeft = tree && run.depth ? 8 + 16 * run.depth + "px" : "";
      return true;
    }
    if (name === "length_m") { td.textContent = number(run.length_m, LENGTH); return true; }
    if (name === "pipe_type_name" && !run.pipe_type_name) {
      td.textContent = "Missing type"; ui.tooltip(td, "Assign a Pipe Type to these lines"); return true;
    }
    return false;
  };
  /* A run's findings behind one alert glyph, each with what to do and a Locate, in a bubble mounted outside the
     table so its scroller and sticky cells never clip it. */
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
      bubble.root.classList.add("piping-findings");
      this.layer.appendChild(bubble.root);
      if (td._findings) td._findings.remove();
      td._findings = trigger;
      td.appendChild(trigger);
    }
    td._findings.hidden = false;
    ui.paintIconButton(bubble.trigger, findings.length + (findings.length === 1 ? " finding" : " findings") +
      " for " + run.display_name, "alert");
    bubble.trigger.classList.toggle("piping-blocks-export", findings.some(function (found) {
      return found.blocks_export;
    }));
    var key = JSON.stringify(findings);
    if (bubble.findings === key) return;
    bubble.findings = key;
    bubble.content.replaceChildren.apply(bubble.content, findings.map(function (finding) {
      var line = ui.element("div", "piping-finding");
      line.appendChild(ui.element("p", finding.blocks_export ? "piping-finding-blocks" : "", finding.message));
      line.appendChild(ui.button("Locate", function () {
        bubble.close(false);
        self.sendLocate(finding.locate.edge_paths);
      }));
      return line;
    }));
  };
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
    var roles = value.totals.by_role;
    tables.table(this.byRole, roles, { rows: roles.map(function (row) {
      return { key: row.role, record: row, tier: "Role", depth: 0, parent: null };
    }), columns: [["role", "Role"], ["run_count", "Runs"], ["line_count", "Lines"],
      ["length_m", header("Length", LENGTH)]], defaultWidths: { role: 160, run_count: 80, line_count: 80 },
    value: function (row, name) { return row.record[name]; }, cell: function (td, row, name) {
      if (name === "role") { td.textContent = shared.roleLabel(row.record.role); return true; }
      if (name === "length_m") { td.textContent = number(row.record.length_m, LENGTH); return true; }
      return false;
    }, empty: "" });
    var systems = (value.systems || []).filter(function (row) {
      var lengths = row.distribution_length_m;
      return lengths.trunk + lengths.branch + lengths.twig + row.recirculation_length_m > 0;
    });
    tables.table(this.bySystem, systems, { rows: systems.map(function (row) {
      return { key: row.hot_water_system_id, record: row, tier: "System", depth: 0, parent: null };
    }), columns: [["system_name", "Hot Water System"], ["trunk", header("Trunk", LENGTH)],
      ["branch", header("Branch", LENGTH)], ["twig", header("Twig", LENGTH)],
      ["recirculation_length_m", header("Recirculation", LENGTH)],
      ["recirculation_temperature_c", header("Recirc.", TEMPERATURE)],
      ["recirculation_hours", header("Recirc.", HOURS)]], defaultWidths: { system_name: 160 },
    value: function (row, name) { return row.record[name]; }, cell: function (td, row, name) {
      var record = row.record;
      if (name === "system_name") { td.textContent = record.name; return true; }
      if (name === "recirculation_temperature_c") td.textContent = number(record[name], TEMPERATURE);
      else if (name === "recirculation_hours") td.textContent = number(record[name], HOURS);
      else td.textContent = number(name === "recirculation_length_m" ? record[name] :
        record.distribution_length_m[name], LENGTH);
      return true;
    }, empty: "" });
  };
  /* Records that cannot be read belong to no run, so they collect here, each with a Locate. */
  Schedule.prototype.paintOthers = function (value) {
    var self = this, items = value ? value.unreadable : [];
    this.others.hidden = !items.length;
    if (!items.length) { this.others.replaceChildren(); return; }
    var list = ui.element("ul", "piping-other-findings");
    items.forEach(function (item) {
      var line = ui.element("li");
      line.appendChild(ui.element("span", "", item.message));
      line.appendChild(ui.button("Locate", function () { self.sendLocate([item.path]); }));
      list.appendChild(line);
    });
    this.others.replaceChildren(ui.element("h2", "", "Not in the schedule (" + value.unreadable_total + ")"), list);
  };
  Schedule.prototype.dispose = function () { this.disposed = true; this.locate.reset(); };
  return { Schedule: Schedule, treeOrder: treeOrder };
});
