/* Shared inventory controls (filter, group, order and direction) and the group heading tables and the library
   sidebar draw. They own view state only; callers supply domain values and labels through the projection config. */
PhComposerUI.define("view_controls", ["dom", "icons"], function (dom, icons) {
  "use strict";
  var element = dom.element, button = dom.button, blank = dom.blank, compareText = dom.compareText,
    glyph = icons.glyph;
  /* A group heading: chevron, category bar, label and count. Shared by tables and the library sidebar. */
  function groupToggle(onToggle) {
    var heading = { button: button("", onToggle) };
    heading.button.className = "phc-group-toggle";
    heading.marker = element("span", "phc-group-chevron");
    heading.marker.setAttribute("aria-hidden", "true"); heading.marker.appendChild(glyph("chevron"));
    heading.bar = element("span"); heading.label = element("span", "phc-group-label");
    heading.count = element("span", "phc-group-count");
    [heading.marker, heading.bar, heading.label, heading.count].forEach(function (node) {
      heading.button.appendChild(node);
    });
    return heading;
  }
  function paintGroupToggle(heading, group) {
    heading.button.setAttribute("aria-expanded", String(!group.collapsed));
    heading.bar.className = "phc-category-bar category-" + (group.tone || "neutral");
    heading.label.textContent = group.label; heading.count.textContent = String(group.count);
  }
  /* `options.guard`, when given, answers why the rows may not be narrowed right now (a draft on a row
     the filter could hide), or null. A refused filter edit keeps its previous text and hands the
     reason to `options.refused`.

     `options.columnSort: true` moves ordering and value filters into the table's column menus
     (column_menu.js): Order by and the direction toggle are hidden, `sortBy` and `filterColumn` set the
     state, and `project` applies a column filter through `config.columnMatch(record, filters)` for a
     top-level record and `config.rowMatch(row, filters)` for a row beneath one.

     `config.queryMatch(row, query, record)`, when given, says whether a row beneath the top-level `record`
     the text filter matched still shows. */
  function ViewControls(options, changed) {
    var self = this, filtered = "";
    this.changed = changed;
    this.columnFilters = Object.create(null);
    function filterChanged() {
      var reason = options.guard && options.guard();
      if (reason) { self.filter.value = filtered; options.refused(reason); return false; }
      filtered = self.filter.value; changed(); return true;
    }
    this.options = options; this.root = element("div", "phc-inventory-controls");
    if (!options.columnSort) this.root.classList.add("has-order-controls");
    this.collapsed = Object.create(null); this.groups = [];
    function select(label, choices, initial, key) {
      var wrap = element("label", "phc-view-control", label), input = element("select");
      choices.forEach(function (choice) {
        var item = element("option", "", choice[1]); item.value = choice[0]; input.appendChild(item);
      });
      if (key) self[key + "Options"] = input;
      input.value = initial; input.setAttribute("aria-label", label); input.addEventListener("change", changed);
      wrap.appendChild(input); self.root.appendChild(wrap); return input;
    }
    // The search field says what it is through its placeholder; its accessible name carries "Filter".
    var filterLabel = element("label", "phc-view-control");
    this.filter = element("input"); this.filter.type = "search"; this.filter.placeholder = options.placeholder;
    this.filter.setAttribute("aria-label", "Filter " + options.label);
    this.filter.addEventListener("input", filterChanged);
    filterLabel.appendChild(this.filter); this.root.appendChild(filterLabel);
    this.clear = button("Clear", function () {
      self.filter.value = "";
      if (filterChanged()) self.filter.focus();
    });
    this.root.appendChild(this.clear);
    this.groupBy = select("Group by", [["", "None"]].concat(options.groups || []), "", "group");
    this.groupBy.parentNode.classList.add("phc-view-group");
    if (options.groups === undefined) this.groupBy.parentNode.hidden = true;
    this.orderBy = select("Order by", options.fields, options.initialOrder || "name", "field");
    this.orderBy.parentNode.classList.add("phc-view-order");
    this._fieldSignature = JSON.stringify(options.fields);
    // One button for the two directions: its icon shows the order in force and its name the change it offers.
    this.direction = { value: "asc" };
    this.directionToggle = icons.iconButton("", "sort_ascending", function () {
      self.direction.value = self.direction.value === "asc" ? "desc" : "asc";
      paintDirection(); changed();
    });
    function paintDirection() {
      var ascending = self.direction.value === "asc";
      icons.paintIconButton(self.directionToggle, ascending ? "Sort descending" : "Sort ascending",
        ascending ? "sort_ascending" : "sort_descending");
    }
    paintDirection();
    this.directionToggle.classList.add("phc-view-direction");
    this.root.appendChild(this.directionToggle);
    this.columnSort = options.columnSort ? { field: options.initialOrder || "name", direction: "asc" } : null;
    if (options.columnSort) { this.orderBy.parentNode.hidden = true; this.directionToggle.hidden = true; }
    this.toggleGroup = function (key) { self.collapsed[key] = !self.collapsed[key]; changed(); };
    /* One button for Collapse all and Expand all: it collapses while anything is open, a partly open
       table included, and expands only once everything is shut. `project` paints which. */
    this.expansionToggle = icons.iconButton("Collapse all", "copy_minus", function () {
      var collapse = self.expansionToggle.getAttribute("data-icon") === "copy_minus";
      if (options.expansion) {
        if (collapse) options.expansion.collapseAll(); else options.expansion.expandAll();
      } else if (collapse) self.groups.forEach(function (group) { self.collapsed[group.key] = true; });
      else self.collapsed = Object.create(null);
      changed();
    });
    this.expansionToggle.classList.add("phc-view-expansion");
    this.root.appendChild(this.expansionToggle);
    this.count = element("span", "phc-view-count"); this.count.setAttribute("role", "status");
    this.root.appendChild(this.count);
  }
  /* A narrowing change asks the guard first; a refused one changes nothing and says why. */
  ViewControls.prototype.allowed = function () {
    var reason = this.options.guard && this.options.guard();
    if (reason) this.options.refused(reason);
    return !reason;
  };
  ViewControls.prototype.sortField = function () {
    return this.columnSort ? this.columnSort.field : this.orderBy.value;
  };
  ViewControls.prototype.sortDirection = function () {
    return this.columnSort ? this.columnSort.direction : this.direction.value;
  };
  /* The direction a column is sorted in, or null when another column orders the rows. */
  ViewControls.prototype.columnDirection = function (field) {
    return this.columnSort && this.columnSort.field === field ? this.columnSort.direction : null;
  };
  ViewControls.prototype.sortBy = function (field, direction) {
    this.columnSort = { field: field, direction: direction === "desc" ? "desc" : "asc" };
    this.changed();
  };
  /* The values a column shows, or null when it shows every value. */
  ViewControls.prototype.columnFilter = function (field) {
    return this.columnFilters[field] ? this.columnFilters[field].slice() : null;
  };
  ViewControls.prototype.filterColumn = function (field, values) {
    if (!this.allowed()) return false;
    if (values) this.columnFilters[field] = values.slice();
    else delete this.columnFilters[field];
    this.changed();
    return true;
  };
  ViewControls.prototype.filterCount = function () { return Object.keys(this.columnFilters).length; };
  ViewControls.prototype.setFields = function (fields) {
    var signature = JSON.stringify(fields);
    if (signature === this._fieldSignature) return;
    var selected = this.orderBy.value;
    this.orderBy.replaceChildren();
    fields.forEach(function (choice) {
      var item = element("option", "", choice[1]); item.value = choice[0]; this.orderBy.appendChild(item);
    }, this);
    this.orderBy.value = selected;
    this._fieldSignature = signature;
  };
  ViewControls.prototype.project = function (records, config) {
    var self = this, query = (this.filter.value || "").trim().toLocaleLowerCase(), groupField = this.groupBy.value;
    var filters = this.columnFilters, filterCount = this.filterCount();
    var sortField = this.sortField(), sign = this.sortDirection() === "desc" ? -1 : 1;
    function id(record) { return config.id ? config.id(record) : record.id; }
    function group(record) {
      var raw = config.value(record, groupField), info = config.group(record, groupField);
      return { key: JSON.stringify([groupField, raw]), label: info.label, tone: info.tone || "neutral",
        blank: blank(raw) };
    }
    var byId = Object.create(null), matches = Object.create(null), retained = Object.create(null),
      groups = Object.create(null), count = 0, retainedCount = 0;
    records.forEach(function (record) {
      var key = id(record);
      byId[key] = record;
      matches[key] = (!config.include || config.include(record)) &&
        (!query || config.search(record).toLocaleLowerCase().indexOf(query) >= 0) &&
        (!filterCount || !config.columnMatch || config.columnMatch(record, filters));
      retained[key] = !matches[key] && config.retain ? config.retain(record) : false;
      if (!matches[key] && !retained[key]) return;
      count += 1;
      if (retained[key]) retainedCount += 1;
      if (!groupField) return;
      var info = group(record);
      if (!groups[info.key]) {
        groups[info.key] = Object.assign(info, { count: 0, collapsed: Boolean(self.collapsed[info.key]) });
      }
      groups[info.key].count += 1;
    });
    var ordered = records.slice().sort(function (a, b) {
      if (groupField) {
        var ag = group(a), bg = group(b),
          order = Number(ag.blank) - Number(bg.blank) || compareText(ag.label, bg.label);
        if (order) return order;
      }
      var av = config.value(a, sortField), bv = config.value(b, sortField);
      if (blank(av) !== blank(bv)) return blank(av) ? 1 : -1;
      var difference = blank(av) ? 0 :
        (typeof av === "number" && typeof bv === "number" ? av - bv : compareText(av, bv));
      return difference * sign ||
        (config.tie ? config.tie(a, b) : compareText(a.name, b.name) || compareText(a.id, b.id));
    });
    this.groups = Object.keys(groups).map(function (key) { return groups[key]; });
    // A nested projection (config.rows) filters a child row by its top-level record.
    var rowIds = Object.create(null);
    if (config.rows) {
      config.rows(ordered).forEach(function (row) {
        rowIds[row.key] = row.parent ? rowIds[row.parent] : id(row.record);
      });
    }
    function rowId(row) { return row.parent ? rowIds[row.key] : id(row.record); }
    var projection = { records: ordered, visibleCount: count, matchedCount: count - retainedCount,
      retainedCount: retainedCount,
      hidden: function (row) {
        var key = rowId(row);
        if (!matches[key] && !retained[key]) return true;
        if (query && row.parent && config.queryMatch && !config.queryMatch(row, query, byId[key])) return true;
        return Boolean(filterCount && row.parent && config.rowMatch && !config.rowMatch(row, filters));
      },
      retained: function (row) { return row.depth === 0 ? retained[rowId(row)] : false; },
      group: groupField ? function (row) {
        var key = id(row.record);
        return matches[key] || retained[key] ? groups[group(row.record).key] : null;
      } : null };
    this.expansionToggle.hidden = !(groupField || this.options.expansion);
    var expansion = this.options.expansion;
    var canCollapse = expansion ? expansion.canCollapse(projection) :
      this.groups.some(function (entry) { return !entry.collapsed; });
    var canExpand = expansion ? expansion.canExpand(projection) :
      this.groups.some(function (entry) { return entry.collapsed; });
    var collapse = canCollapse || !canExpand;
    icons.paintIconButton(this.expansionToggle, collapse ? "Collapse all" : "Expand all",
      collapse ? "copy_minus" : "copy_plus");
    this.expansionToggle.disabled = !canCollapse && !canExpand;
    this.clear.hidden = !query;
    // The row says how many records there are, and how many a filter leaves; the page header counts nothing.
    // `count` may be false (no count) or a function (shown, total, filtered) giving the screen's own words.
    var counted = this.options.count;
    var narrowed = Boolean(query || filterCount);
    this.count.textContent = counted === false ? "" : typeof counted === "function" ?
      counted(count, records.length, narrowed, filterCount) :
      (narrowed ? count + " of " + records.length : records.length + " total");
    return projection;
  };
  return { ViewControls: ViewControls, groupToggle: groupToggle, paintGroupToggle: paintGroupToggle };
});
