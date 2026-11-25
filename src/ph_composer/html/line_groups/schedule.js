/* A line group's schedule on its feature's pill: one row per run as the last read found it, then the totals. Grouping,
   ordering and the text filter are view state. A row click selects the run's lines (runs.locate) and opens the group
   holding them; findings sit behind an alert glyph, each with its own Locate; records that cannot be read collect
   under "Not in the schedule". The read is the owner's (line_groups/shared.js): this view shows it, says when the
   Model has changed since, and offers Refresh. The feature gives its columns and words:

     { columns, widths, field(run, name), cell(td, run, name, schedule) (true when drawn), order(runs) (each run
       with a unique `key` and its `order`), groups, initialGroup, placeholder, search(run), toggles, empty,
       totals: [{ title, rows(value), key(row), columns(), widths, cell(td, row, name) }],
       totalsShown(value) (optional: whether the totals show; by default once there is a run) }

   A column named `length_m` carries the length unit in its header. */
PhComposerUI.define("line_groups/schedule", ["request", "workspace", "table", "view_controls", "fields", "units",
  "unit_preferences", "sections/colour_by", "line_groups/shared"],
function (request, ui, tables, viewControls, fields, units, preferences, colourBy, shared) {
  "use strict";
  var LENGTH = fields.LENGTH_M;

  function number(value, descriptor, showUnit) {
    return value === null || value === undefined ? "—" : units.format(value, descriptor,
      units.profile(descriptor, preferences.current()), { showUnit: Boolean(showUnit) });
  }
  function header(label, descriptor) { return units.header(label, descriptor, preferences.current()); }

  /* `spec` is the feature's line group spec, `view` its schedule's; `notify(message, tone)` raises the panel's
     notice. */
  function Schedule(root, session, send, spec, view, read, refresh, notify) {
    var self = this;
    this.spec = spec; this.view = view; this.read = read; this.runs = []; this.notify = notify;
    this.locate = request.channel(session, send, spec.key + "-locate", "view.invoke");
    this.toggles = new colourBy.HeaderToggles(view.toggles);
    this.controls = new viewControls.ViewControls({ label: spec.noun + " runs", placeholder: view.placeholder,
      fields: [["order", "Schedule order"]].concat(view.columns), initialOrder: "order", groups: view.groups,
      count: function (shown, total, narrowed) {
        return narrowed ? shown + " of " + total + " runs" : total + (total === 1 ? " run" : " runs");
      } }, function () { self.paint(); });
    this.controls.groupBy.value = view.initialGroup;
    this.status = ui.element("span", "line-group-status");
    this.status.setAttribute("role", "status");
    this.refresh = ui.button("Refresh", function () { refresh(); });
    this.refresh.setAttribute("aria-label", "Refresh the schedule and the " + spec.label + "s");
    this.controls.root.appendChild(this.refresh);
    this.controls.root.appendChild(this.status);
    root.appendChild(ui.element("h2", "line-group-schedule-title", "Schedule"));
    root.appendChild(this.controls.root);
    this.mount = ui.element("div", "line-group-table line-group-schedule");
    this.mount.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || !target.closest || target.closest("button, input, select, a, .col-actions")) return;
      var row = target.closest("[data-row-key]"), key = row && row.getAttribute("data-row-key");
      var run = self.runs.filter(function (entry) { return entry.key === key; })[0];
      if (run) self.sendLocate(run.edge_paths);
    });
    root.appendChild(this.mount);
    this.totals = ui.element("div", "line-group-totals");
    this.totals.appendChild(ui.element("h2", "", "Totals"));
    this.parts = view.totals.map(function (part) {
      var mount = ui.element("div", "line-group-table");
      self.totals.appendChild(ui.element("h3", "", part.title));
      self.totals.appendChild(mount);
      return { part: part, mount: mount };
    });
    root.appendChild(this.totals);
    this.others = ui.element("div", "line-group-others");
    root.appendChild(this.others);
    this.bubbles = Object.create(null);
    this.layer = ui.element("div", "line-group-findings-layer");
    root.appendChild(this.layer);
  }
  Schedule.prototype.guard = function () { return this.locate.busy() ? "Wait for Locate to finish." : null; };
  /* Locate may open a group, an Undo step of its own and so a new revision, but changes no data: a read current when
     it was sent takes the revision Locate answers with, and only that one. A refusal is a notice. */
  Schedule.prototype.sendLocate = function (paths) {
    if (this.disposed || this.locate.busy()) return;
    var read = this.read, current = this.state && !read.stale(this.state) ? read.result : null;
    this.locate.run(this.spec.prefix + "runs.locate", { edge_paths: JSON.parse(JSON.stringify(paths)) }, {
      onDone: function (outcome) {
        if (current && read.result === current && outcome.revision !== undefined) current.revision = outcome.revision;
      } });
    this.paint();
  };
  Schedule.prototype.render = function (state, shown) {
    if (this.disposed) return;
    var located = this.locate.consume(state);
    if (located && located.status === "refused") this.notify(located.message, "warning");
    this.state = state;
    if (!shown) return;
    var value = this.read.value();
    if (value !== this.painted) {
      this.painted = value;
      this.runs = value ? this.view.order(value.runs) : [];
      this.pruneBubbles();
    }
    this.paint();
  };
  Schedule.prototype.groupName = function (run) { return shared.groupLabel(this.spec, run.group.name,
    run.group.group_path); };
  Schedule.prototype.paint = function () {
    if (this.disposed || !this.state) return;
    var self = this, view = this.view, value = this.read.value(), state = this.state;
    this.status.textContent = this.read.busy() ? "Reading the Model..." : this.read.error ||
      (this.read.stale(state) ? "Changed since read" : "");
    this.status.classList.toggle("line-group-error", Boolean(this.read.error) && !this.read.busy());
    this.refresh.disabled = this.read.busy();
    // Two groups may share a name: grouping keys on the occurrence path, and a shared name shows its path.
    var named = Object.create(null);
    this.runs.forEach(function (run) {
      var key = run.group.group_path.join("/"), name = self.groupName(run);
      named[name] = named[name] || Object.create(null);
      named[name][key] = true;
    });
    function field(run, name) { return name === "group" ? self.groupName(run) : view.field(run, name); }
    var projected = this.controls.project(this.runs, { id: function (run) { return run.key; },
      value: field, groupKey: function (run, name) {
        return name === "group" ? run.group.group_path.join("/") : field(run, name);
      }, search: view.search, group: function (run, name) {
        var label = String(field(run, name) || "None"), path = run.group.group_path.join("/");
        return { label: name === "group" && Object.keys(named[label] || {}).length > 1 ? label + " (" + path + ")" :
          label };
      },
      tie: function (a, b) { return a.order - b.order; } });
    var rows = projected.records.map(function (run) {
      return { key: run.key, record: run, tier: "Run", depth: 0, parent: null };
    });
    tables.table(this.mount, this.runs, { rows: rows, defaultWidths: view.widths,
      columns: [["actions", "Actions"]].concat(view.columns.map(function (column) {
        return [column[0], column[0] === "length_m" ? header(column[1], LENGTH) : column[1]];
      })),
      headerActions: function (name) { return self.toggles.actions(state, name); },
      rowHidden: projected.hidden, group: projected.group, visibleCount: projected.visibleCount,
      toggleGroup: function (key) { self.controls.toggleGroup(key); },
      value: function (row, name) { return field(row.record, name); },
      cell: function (td, row, name) {
        if (view.cell && view.cell(td, row.record, name, self)) return true;
        if (name === "length_m") { td.textContent = number(row.record.length_m, LENGTH); return true; }
        return false;
      },
      actions: function (row) {
        return [{ id: "locate", icon: "locate", label: "Locate " + row.record.display_name }];
      },
      action: function (row) { self.sendLocate(row.record.edge_paths); },
      actionsCell: function (td, row) { self.findingsCell(td, row.record); },
      disabled: this.locate.busy(),
      empty: value ? (this.runs.length ? "No runs match this view." : view.empty) :
        this.read.error || "Reading the schedule..." });
    this.paintTotals(value);
    this.paintOthers(value);
  };
  /* A run's findings behind one alert glyph, each with what to do and a Locate, in a bubble mounted outside the
     table so its scroller and sticky cells never clip it. */
  Schedule.prototype.findingsCell = function (td, run) {
    var self = this, findings = run.findings || [], bubble = this.bubbles[run.key];
    if (!findings.length) {
      if (td._findings) td._findings.hidden = true;
      if (bubble) bubble.close(false);
      return;
    }
    if (!bubble || td._findings !== bubble.trigger) {
      if (bubble) bubble.root.remove();
      var trigger = ui.iconButton("", "alert");
      trigger.classList.add("row-icon");
      bubble = this.bubbles[run.key] = new ui.Bubble(trigger, "Findings", { detachedTrigger: true });
      bubble.root.classList.add("line-group-findings");
      this.layer.appendChild(bubble.root);
      if (td._findings) td._findings.remove();
      td._findings = trigger;
      td.appendChild(trigger);
    }
    td._findings.hidden = false;
    ui.paintIconButton(bubble.trigger, findings.length + (findings.length === 1 ? " finding" : " findings") +
      " for " + run.display_name, "alert");
    bubble.trigger.classList.toggle("line-group-blocks-export", findings.some(function (found) {
      return found.blocks_export;
    }));
    var key = JSON.stringify(findings);
    if (bubble.findings === key) return;
    bubble.findings = key;
    bubble.content.replaceChildren.apply(bubble.content, findings.map(function (finding) {
      var line = ui.element("div", "line-group-finding");
      line.appendChild(ui.element("p", finding.blocks_export ? "line-group-finding-blocks" : "", finding.message));
      line.appendChild(ui.button("Locate", function () {
        bubble.close(false);
        self.sendLocate(finding.locate.edge_paths);
      }));
      return line;
    }));
  };
  Schedule.prototype.pruneBubbles = function () {
    var kept = Object.create(null);
    this.runs.forEach(function (run) { kept[run.key] = true; });
    Object.keys(this.bubbles).forEach(function (key) {
      if (kept[key]) return;
      this.bubbles[key].close(false);
      this.bubbles[key].root.remove();
      delete this.bubbles[key];
    }, this);
  };
  Schedule.prototype.paintTotals = function (value) {
    this.totals.hidden = !value || !(this.view.totalsShown ? this.view.totalsShown(value) : value.runs.length);
    if (this.totals.hidden) return;
    this.parts.forEach(function (held) {
      var part = held.part, rows = part.rows(value);
      tables.table(held.mount, rows, { rows: rows.map(function (row) {
        return { key: part.key(row), record: row, tier: "Total", depth: 0, parent: null };
      }), columns: part.columns(), defaultWidths: part.widths,
      value: function (row, name) { return row.record[name]; },
      cell: function (td, row, name) { return part.cell(td, row.record, name); }, empty: "" });
    });
  };
  /* Records that cannot be read belong to no run, so they collect here, each with a Locate. */
  Schedule.prototype.paintOthers = function (value) {
    var self = this, spec = this.spec, items = value ? value.unreadable : [];
    this.others.hidden = !items.length;
    if (!items.length) { this.others.replaceChildren(); return; }
    var list = ui.element("ul", "line-group-other-findings");
    // Locate selects lines, so a group's own record names its place instead.
    var groups = this.read.groupRows || [];
    items.forEach(function (item) {
      var line = ui.element("li"), group = groups.filter(function (row) {
        return row.path.join("/") === item.path.join("/");
      })[0];
      line.appendChild(ui.element("span", "", (group ? shared.groupLabel(spec, group.name, group.path) + ": " : "") +
        item.message));
      if (!group) line.appendChild(ui.button("Locate", function () { self.sendLocate([item.path]); }));
      list.appendChild(line);
    });
    this.others.replaceChildren(ui.element("h2", "", "Not in the schedule (" + value.unreadable_total + ")"), list);
  };
  Schedule.prototype.dispose = function () { this.disposed = true; this.locate.reset(); };
  return { Schedule: Schedule, number: number, header: header };
});
