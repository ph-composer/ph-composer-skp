/* Stable local-record rows and read-only details. Use is the only command owned by this placement. */
PhComposerUI.define("library/rows", ["units", "workspace"], function (units, ui) {
  "use strict";
  var el = ui.element;
  var OPEN_UP_TO = 20;
  var methods = {};
  /* The category choice lists the categories the records in hand use, by their labels, and keeps the user's
     choice while it still names one of them. */
  methods.paintCategories = function (categories) {
    var adapter = this.adapter, chosen = this.category.value, seen = Object.create(null);
    this.records.forEach(function (row) { seen[adapter.category(row)] = true; });
    var keys = Object.keys(seen).sort(function (a, b) { return adapter.compare(a, b); });
    var signature = keys.join("\u0000");
    if (this.categorySignature !== signature) {
      this.categorySignature = signature;
      this.category.replaceChildren(ui.option("", "All categories"));
      keys.forEach(function (key) {
        var info = categories.filter(function (entry) { return entry.id === key; })[0];
        this.category.appendChild(ui.option(key, info ? info.label : (key || "Uncategorized")));
      }, this);
    }
    this.category.value = keys.indexOf(chosen) >= 0 ? chosen : "";
    this.narrowing.hidden = this.narrowing.hidden || !this.records.length;
  };
  methods.renderList = function () {
    var self = this, adapter = this.adapter, query = this.search.value.trim().toLowerCase();
    var categories = adapter.categories(this.state), grouped = Object.create(null);
    this.visible = [];
    var scrollTop = this.list.scrollTop;
    this.list.replaceChildren();
    var repeats = this.besideTable && !(this.store && this.store.selected);
    this.search.hidden = this.count.hidden = this.narrowing.hidden = repeats;
    this.list.removeAttribute("aria-busy");
    if (repeats) return;
    var selected = Boolean(this.store && this.store.selected), page = selected ? this.store.page : null;
    var loading = this.loading() || (selected && this.store.busy());
    if (loading) this.list.setAttribute("aria-busy", "true");
    this.paintCategories(categories);
    var only = this.category.value, sign = this.order.value === "desc" ? -1 : 1;
    this.records.filter(function (row) {
      return adapter.searchText(row).toLowerCase().includes(query) && (!only || adapter.category(row) === only);
    }).sort(function (a, b) { return sign * adapter.compare(adapter.name(a), adapter.name(b)); })
      .forEach(function (row) {
        var category = adapter.category(row);
        (grouped[category] || (grouped[category] = [])).push(row);
      });
    // A short list opens every group; a long one starts folded, so its categories read as a table of contents.
    // A search opens whatever it found. A group the user folded or opened stays that way.
    var shown = Object.keys(grouped).reduce(function (total, key) { return total + grouped[key].length; }, 0);
    function open(key) {
      if (query) return true;
      return Object.prototype.hasOwnProperty.call(self.expanded, key) ? self.expanded[key] !== false :
        shown <= OPEN_UP_TO;
    }
    Object.keys(grouped).sort(function (a, b) { return sign * adapter.compare(a, b); }).forEach(function (key) {
      var info = categories.filter(function (entry) { return entry.id === key; })[0];
      var group = el("section", "library-sidebar-group");
      var heading = ui.button(info ? info.label : (key || "Uncategorized"), function () {
        self.expanded[key] = !open(key);
        self.renderList();
      });
      heading.className = "library-sidebar-group-heading";
      heading.setAttribute("aria-expanded", String(open(key)));
      heading.appendChild(el("span", "library-sidebar-group-count", String(grouped[key].length)));
      group.appendChild(heading);
      if (open(key)) grouped[key].forEach(function (row) {
        var entry = self.entries[row.id];
        if (!entry) entry = self.entries[row.id] = self.makeRow(row);
        entry.row = row;
        entry.decoration.replaceChildren();
        adapter.decorate(entry.decoration, row);
        if (entry.badge) entry.badge.remove();
        if (row.resolution && row.resolution.candidates.length) {
          entry.badge = el("small", "library-local-badge", "In this file"); entry.button.appendChild(entry.badge);
        }
        entry.name.textContent = adapter.name(row);
        // A library's record says where its click leads; a record already in the file has nothing to add.
        // While its library loads, nothing is copied from it, so the row offers no add.
        var known = Boolean(row.resolution && row.resolution.candidates.length), locked = self.copyLocked(row);
        if (row.library && !entry.addGlyph) entry.button.appendChild(entry.addGlyph = ui.glyph("add"));
        if (entry.addGlyph) entry.addGlyph.hidden = !row.library || known || locked;
        ui.tooltip(entry.button, !row.library ? "" : known ? adapter.name(row) + " is already in this file" :
          locked ? "The library is still loading" : "Add " + adapter.name(row) + " to this file");
        entry.bubble.panel.setAttribute("aria-label", adapter.name(row));
        entry.bubble.heading.querySelector("strong").textContent = adapter.name(row);
        entry.bubble.closeButton.setAttribute("aria-label", "Close " + adapter.name(row));
        self.visible.push(entry);
        group.appendChild(entry.root);
      });
      self.list.appendChild(group);
    });
    this.list.scrollTop = scrollTop;
    // A library's count waits for the total its catalog reports; a hosted load reports none while it runs.
    var total = selected ? page && page.total : this.records.length;
    this.count.hidden = typeof total !== "number";
    this.count.textContent = this.count.hidden ? "" :
      this.visible.length + " shown · " + total + (selected ? " in library" : " in this file");
    if (!Object.keys(grouped).length) {
      var empty = query ? "No records match this search." : adapter.emptyText;
      // Loading, no catalog and an empty catalog are three states: only a catalog read in full can be empty.
      if (selected && !this.records.length) {
        empty = loading ? "Loading library…" : page && page.generation && !this.store.error ?
          "No records in this library." : "No catalog is available.";
      }
      var note = el("p", "muted", empty);
      // The status line above announces the load; the list shows it where the rows will be, said once.
      if (selected && loading && !this.records.length) note.setAttribute("aria-hidden", "true");
      this.list.appendChild(note);
    }
  };
  methods.makeRow = function (row) {
    var self = this, entry = { row: row, root: el("div", "library-sidebar-row") };
    entry.button = ui.button("", function (event) {
      var suppressed = entry.suppressClick && event.detail !== 0;
      entry.suppressClick = false;
      if (!suppressed) self.openDetails(entry);
    });
    entry.button.className = "library-sidebar-row-button";
    entry.button.setAttribute("data-library-row", row.id);
    // A row is reused across repaints, so its decoration (a Material's swatch) is redrawn from each new record.
    entry.decoration = el("span", "library-sidebar-decoration");
    entry.button.appendChild(entry.decoration);
    entry.name = el("span", "library-sidebar-name", this.adapter.name(row));
    entry.button.appendChild(entry.name);
    entry.button.addEventListener("mousedown", function (event) { self.drag.start(entry, event); });
    entry.button.addEventListener("keydown", function (event) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        var next = self.visible[self.visible.indexOf(entry) + (event.key === "ArrowDown" ? 1 : -1)];
        if (next) next.button.focus();
      }
    });
    entry.bubble = new ui.Bubble(entry.button, this.adapter.name(row), { side: true, ownTrigger: true,
      onOpen: function () { self.detail = entry; self.renderDetails(); } });
    entry.bubble.panel.classList.add("library-record-card");
    entry.root.appendChild(entry.bubble.root);
    return entry;
  };
  methods.openDetails = function (entry) {
    if (this.disposed || !this.enabled || !entry) return;
    this.detail = entry;
    this.renderDetails();
    entry.bubble.open();
  };
  methods.closeDetails = function () {
    if (this.detail) this.detail.bubble.close(false);
    this.detail = null;
  };
  methods.renderDetails = function () {
    var self = this, entry = this.detail;
    if (!entry) return;
    var content = entry.bubble.content, values = entry.row.values, library = entry.row.library;
    if (library) {
      content.replaceChildren(el("small", "muted", "Library: " + library.library_name));
      content.appendChild(el("strong", "", "Copied properties"));
    } else content.replaceChildren();
    this.adapter.properties.forEach(function (item) {
      var value = values[item[1]];
      content.appendChild(ui.propertyRow(item[0], item[2] ? units.format(value, item[2], units.profile(item[2])) :
        (ui.blank(value) ? "—" : value), ""));
    });
    content.appendChild(el("p", "muted", values.notes || "No notes."));
    if (library) {
      var sourceProperties = this.adapter.sourceProperties || [];
      if (sourceProperties.length) content.appendChild(el("strong", "", "Source information"));
      sourceProperties.forEach(function (item) {
        content.appendChild(ui.propertyRow(item[0], values[item[1]] || "—", ""));
      });
      entry.add = ui.button("Add to file", function () { self.add(entry.row); }); content.appendChild(entry.add);
    }
    entry.use = ui.button("Use", function () { self.use(entry.row); });
    entry.use.setAttribute("aria-label", "Use on selected target");
    entry.hint = el("small", "muted");
    content.appendChild(entry.hint);
    content.appendChild(entry.use);
    this.paintActions();
  };
  methods.paintActions = function () {
    if (!this.detail) return;
    var target = this.adapter.target(this.context), locked = this.copyLocked(this.detail.row);
    this.detail.use.hidden = !this.onUse;
    this.detail.use.disabled = !this.enabled || this.busy() || locked || Boolean(target.hint);
    if (this.detail.add) this.detail.add.disabled = !this.enabled || this.busy() || locked;
    this.detail.hint.textContent = locked ? "The library is still loading." : this.onUse ? (target.hint || "") : "";
  };
  return methods;
});
