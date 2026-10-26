/* A record inventory: the shared table, view controls, cell edits and range edits over one snapshot
 * section. The feature supplies every record value, label and action through `config`.
 * `config.columnMenus` ({ sort: [field], filter: [field] }), when given, sorts and filters from each named
 * column's menu (column_menu.js) in place of Order by; a filter offers the column's values as shown, its
 * declared choices included. */
PhComposerUI.define("inventory", ["request", "snapshot", "workspace", "table", "view_controls", "record_edits",
  "inventory_grid", "units", "unit_preferences", "column_menu"],
function (request, snapshot, ui, tables, viewControls, RecordEdits, Grid, units, preferences, columnMenus) {
  "use strict";
  function RangeEdits(session, send, action, notice, changed) {
    this.requests = request.channel(session, send, "range-edits");
    this.action = action;
    this.notice = notice;
    this.changed = changed;
    this.queue = [];
    this.disposed = false;
  }
  RangeEdits.prototype.busy = function () { return this.requests.busy() || this.queue.length > 0; };
  RangeEdits.prototype.submit = function (changes) {
    if (this.disposed || this.enabled === false || this.busy()) return;
    this.queue = JSON.parse(JSON.stringify(changes));
    this.next();
  };
  RangeEdits.prototype.next = function () {
    if (!this.requests.busy() && this.queue.length) this.requests.run(this.action, this.queue.shift());
    this.changed();
  };
  RangeEdits.prototype.refresh = function (state) {
    var outcome = this.requests.consume(state);
    if (!outcome) return;
    if (outcome.status !== "completed") {
      this.queue = [];
      this.notice(outcome.message || "The remaining range edits were not applied.");
    } else this.next();
  };
  RangeEdits.prototype.withdraw = function () {
    this.enabled = false;
    this.queue = [];
    this.requests.reset();
  };
  RangeEdits.prototype.dispose = function () {
    this.disposed = true;
    this.withdraw();
  };
  // Inventory owns the shared mechanics; the feature supplies every record value, label and action. A display
  // preference change reaches it through the panel's one repaint, so it holds no preference subscription.
  function Inventory(root, session, send, notice, changed, config) {
    var self = this;
    this.root = root;
    this.config = config;
    this.records = [];
    this.requests = request.channel(session, send, config.label + "-action");
    this.ranges = new RangeEdits(session, send, config.action, notice, changed);
    this.edits = new RecordEdits(session, send, notice, { action: config.action, fields: config.editable,
      quantities: config.quantities, selectFields: config.selectFields, requiredFields: ["name"],
      normalize: config.normalize, validate: config.validate, navigateOnCommit: false,
      enabled: function (state) { return Boolean(snapshot.value(state, config.section)) &&
          !self.ranges.busy() && !self.externalBusy; },
      label: function (row, field) { return row.record.values.name + " " + self.columnLabel(field); },
      recordLabel: config.label });
    this.menus = Object.create(null);
    this.controls = new viewControls.ViewControls({ label: config.label, placeholder: "Name or notes",
      fields: config.columns, groups: config.groups, count: config.count, columnSort: Boolean(config.columnMenus),
      guard: function () { return self.guard(); }, refused: notice },
      function () {
        if (self.dirty()) self.controls.collapsed = Object.create(null);
        changed();
      });
    this.unreadable = ui.element("p", "phc-inventory-warning");
    this.unreadable.setAttribute("role", "status");
    root.appendChild(this.unreadable);
    this.scroll = ui.element("div", "phc-table-scroll phc-inventory-table");
    this.grid = new Grid({ edits: this.edits, scroll: this.scroll, toolbarParent: this.controls.root,
      hiddenColumns: function () { return {}; }, isBusy: function () { return self.busy(); }, notify: notice,
      submitBatch: function (changes) { self.ranges.submit(changes); } });
    // A feature's tab settings (`config.settings`, nodes it owns) end the action bar after the view controls.
    if (config.settings && config.settings.length) {
      this.settingsRoot = ui.element("div", "phc-inventory-settings");
      config.settings.forEach(function (node) { self.settingsRoot.appendChild(node); });
      this.controls.root.appendChild(this.settingsRoot);
    }
    root.appendChild(this.controls.root);
    root.appendChild(this.scroll);
  }
  Inventory.prototype.columnLabel = function (field) {
    return this.config.columns.filter(function (entry) { return entry[0] === field; })[0][1];
  };
  /* A value as a filter compares it: a blank is "". */
  function filterKey(value) { return value === null || value === undefined ? "" : String(value); }
  /* The values a column offers to filter by: its declared choices in their order, then any other value a record
     holds, the blank last. */
  Inventory.prototype.filterValues = function (field) {
    var config = this.config, choices = (config.selectFields || {})[field] || [], seen = Object.create(null);
    var values = [], labels = Object.create(null);
    function add(value, label) {
      if (seen[value]) return;
      seen[value] = true; values.push(value); labels[value] = label;
    }
    choices.forEach(function (choice) {
      if (typeof choice === "string") add(choice, choice); else add(choice.value, choice.label);
    });
    this.records.forEach(function (record) {
      var value = filterKey(config.value(record, field));
      add(value, value || "None");
    });
    return values.sort(function (a, b) { return Number(!a) - Number(!b); }).map(function (value) {
      return { value: value, label: labels[value] || "None" };
    });
  };
  Inventory.prototype.columnMenu = function (field, label) {
    var self = this, spec = this.config.columnMenus, menu = this.menus[field], controls = this.controls;
    if (!menu) {
      menu = this.menus[field] = new columnMenus.ColumnMenu({ label: label,
        sort: spec.sort && spec.sort.indexOf(field) >= 0 ? { current: function () {
          return controls.columnDirection(field);
        }, choose: function (direction) { controls.sortBy(field, direction); } } : null,
        filter: spec.filter && spec.filter.indexOf(field) >= 0 ? {
          values: function () { return self.filterValues(field); },
          shown: function () { return controls.columnFilter(field); },
          set: function (values) { return controls.filterColumn(field, values); } } : null });
    }
    // The label carries a unit, which a unit switch changes.
    menu.options.label = label;
    menu.paint();
    return menu;
  };
  Inventory.prototype.dirty = function (id) {
    return Object.keys(this.edits.cells).some(function (key) {
      var cell = this.edits.cells[key];
      return (!id || cell.row.record.id === id) && cell.status !== "clean";
    }, this);
  };
  Inventory.prototype.busy = function () {
    return this.ranges.busy() || this.requests.busy() || Boolean(this.edits.pending) || Boolean(this.externalBusy);
  };
  Inventory.prototype.guard = function () {
    if (this.disposed) return "This inventory belongs to a previous Model.";
    if (this.busy()) return "Wait for the Model operation to finish.";
    return this.dirty() ? "Finish or cancel the cell draft before changing sections or hiding rows." : null;
  };
  Inventory.prototype.render = function (state) {
    if (this.disposed) return;
    var self = this, config = this.config, payload = snapshot.value(state, config.section);
    this.records = payload ? payload.records : [];
    this.enabled = Boolean(payload);
    this.unreadable.textContent = payload ? (payload.unreadable || []).map(function (record) {
      return record.id + ": " + record.message;
    }).join(" ") : "";
    this.unreadable.hidden = !this.unreadable.textContent;
    this.ranges.enabled = Boolean(payload);
    if (!payload) {
      this.ranges.withdraw();
      this.requests.reset();
    }
    this.ranges.refresh(state);
    var outcome = this.requests.consume(state);
    if (outcome && outcome.status !== "completed") config.notice(snapshot.message(outcome,
      "The action was not applied."));
    var columns = config.columns.map(function (entry) {
      var descriptor = (config.quantities || {})[entry[0]];
      return [entry[0], descriptor ? units.header(entry[1], descriptor, preferences.current()) : entry[1]];
    });
    this.controls.setFields(columns);
    if (this.dirty()) this.controls.collapsed = Object.create(null);
    var projected = this.controls.project(this.records, { value: config.value,
      search: function (record) { return record.values.name + " " + (record.values.notes || ""); },
      group: config.group, columnMatch: function (record, filters) {
        return Object.keys(filters).every(function (field) {
          return filters[field].indexOf(filterKey(config.value(record, field))) >= 0;
        });
      }, tie: function (a, b) {
        return ui.compareText(a.values.name, b.values.name) || ui.compareText(a.id, b.id);
      }, retain: function (record) { return self.dirty(record.id); } });
    var rows = projected.records.map(function (record) {
      return { key: record.id, record: record, tier: config.label, depth: 0, parent: null };
    });
    this.edits.batchPending = this.ranges.busy();
    this.edits.refresh(rows, state);
    this.tableOptions = { rows: rows, columns: [["actions", "Actions"]].concat(columns), stickyWidths: {},
      defaultWidths: { name: 220, notes: 240, color: 72, category: 210, exterior_condition: 175 },
      disabled: !payload || this.busy(),
      value: function (row, field) { return config.value(row.record, field); },
      rowHidden: projected.hidden, group: projected.group, visibleCount: projected.visibleCount,
      toggleGroup: function (key) {
        var reason = self.guard();
        if (reason) config.notice(reason);
        else self.controls.toggleGroup(key);
      }, actions: config.actions, action: config.actionFor, actionsCell: config.actionsCell,
      cell: function (td, row, field, value) {
        if (config.cell && config.cell(td, row, field, value)) return true;
        if (!self.edits.render(td, row, field)) return false;
        self.grid.bind(td, row, field, !payload || self.ranges.busy());
        if (config.afterCell) config.afterCell(td, row, field);
        return true;
      // With no records at all the next step is to make one; a filter that hides them all says that instead.
      }, empty: payload ? (this.records.length ? "No " + config.label + " records match this view." :
        "No " + config.label + " records yet. Choose + New " + config.label + ".") :
        snapshot.message(snapshot.section(state, config.section) || {}, config.label + " records are unavailable.") };
    if (config.columnMenus) {
      var labels = Object.create(null), spec = config.columnMenus;
      columns.forEach(function (column) { labels[column[0]] = column[1]; });
      this.tableOptions.headerActions = function (field) {
        if ((spec.sort || []).indexOf(field) < 0 && (spec.filter || []).indexOf(field) < 0) return [];
        var menu = self.columnMenu(field, labels[field]);
        return [{ node: menu.root, persistent: menu.filtered() }];
      };
    }
    if (config.tableId) this.tableOptions = ui.composeTable(config.tableId, this.tableOptions, state,
      this.requests.transport);
    var composedAction = this.tableOptions.action;
    this.tableOptions.action = function (row, action, control) {
      if (action.tableContributor) {
        var reason = self.guard();
        if (reason) { config.notice(reason); return; }
      }
      composedAction(row, action, control);
    };
    tables.table(this.scroll, this.records, this.tableOptions);
    this.grid.refresh();
  };
  Inventory.prototype.dispose = function () {
    this.disposed = true;
    this.edits.dispose();
    this.grid.dispose();
    this.ranges.dispose();
    this.requests.reset();
  };
  return { Inventory: Inventory, RangeEdits: RangeEdits };
});
