/* One persistent kind browser beside a work surface. The selected source is local or one provider. */
PhComposerUI.define("library/sidebar", ["library/adapters", "library/drag", "library/rows", "library/store",
  "library/copy", "library/setup", "workspace"],
  function (adapters, Drag, rows, Store, Copy, Setup, ui) {
    "use strict";
    var el = ui.element;
    // Catalog notes for rows admission left out (context/CONTRACTS.md, "Catalog notes"), worded here:
    // a note carries only codes and identities, never a provider's text. A row kept with an optional
    // field absent or an unknown field dropped is normalized; any other note (a skipped file, a
    // provider's own code, a skip that names no record) is reported without a list.
    var SKIPPED = {
      "library.row_required_invalid": "a required value, such as its name, is missing or not valid",
      "library.row_optional_invalid": "a value is outside what PH-Composer accepts",
      "library.unit_invalid": "a value has no unit PH-Composer reads",
      "library.row_semantic_invalid": "its values are not valid",
      "library.row_label_invalid": "its name is blank"
    };
    var KEPT = { "library.row_optional_absent": true, "library.row_fields_omitted": true };
    var SKIPPED_SHOWN = 20;
    function Sidebar(options) {
      var self = this;
      this.adapter = adapters.adapter(options.adapter);
      this.onUse = options.onUse;
      // Beside the table of the same records, the local list would only repeat it.
      this.besideTable = Boolean(options.besideTable);
      this.ownerBusy = options.busy || function () { return false; };
      this.changed = options.changed || function () {};
      this.entries = Object.create(null);
      this.expanded = Object.create(null);
      this.context = {};
      this.records = [];
      this.enabled = false;
      this.collapsed = window.innerWidth < 900;
      this.root = el("aside", "library-sidebar-root");
      this.root.setAttribute("aria-label", this.adapter.title);
      this.toggleButton = ui.button(this.adapter.title, function () { self.toggle(); });
      this.toggleButton.className = "library-sidebar-toggle";
      this.toggleButton.setAttribute("data-editor-local", "");
      this.content = el("div", "library-sidebar-content");
      this.source = el("select", "library-sidebar-source");
      this.source.setAttribute("aria-label", "Library source");
      this.source.addEventListener("change", function () {
        if (!self.store || self.ownerBusy() || (self.copy && (!self.copy.root.hidden || self.copy.busy()))) {
          self.source.value = self.store ? self.store.selected : ""; return;
        }
        self.closeDetails(); self.drag.end(); self.store.select(self.source.value); self.updateRows();
      });
      this.content.appendChild(this.source);
      this.sourceStatus = el("small", "muted"); this.sourceStatus.setAttribute("role", "status");
      this.content.appendChild(this.sourceStatus);
      this.skipped = el("ul", "library-sidebar-skipped"); this.skipped.setAttribute("aria-label", "Records not loaded");
      this.skipped.hidden = true; this.content.appendChild(this.skipped);
      this.refreshButton = ui.button("Refresh", function () { if (!self.busy()) self.store.refresh(); });
      this.setupButton = ui.button("Library setup…", function () { if (!self.busy()) self.setup.open(); });
      var controls = el("div", "library-source-controls");
      // A work surface that needs a record the library lacks makes one here without leaving (options.create).
      if (options.create) {
        this.createButton = ui.button(options.create.label, function () { if (!self.busy()) options.create.run(); });
        controls.appendChild(this.createButton);
      }
      controls.appendChild(this.refreshButton);
      controls.appendChild(this.setupButton); this.content.appendChild(controls);
      if (options.localOnly) { this.source.hidden = true; controls.hidden = true; }
      this.search = el("input");
      this.search.type = "search";
      this.search.placeholder = "Search name, category or notes";
      this.search.setAttribute("aria-label", "Search " + this.adapter.title.toLowerCase());
      this.search.addEventListener("input", function () { self.renderList(); });
      // Narrowing beside search: one category, or all, and the name order. Both are view state only.
      this.category = el("select", "phc-choice-pill library-sidebar-category");
      this.category.setAttribute("aria-label", "Show category");
      this.category.addEventListener("change", function () { self.renderList(); });
      this.order = el("select", "phc-choice-pill library-sidebar-order");
      this.order.setAttribute("aria-label", "Order by name");
      this.order.appendChild(ui.option("asc", "A to Z")); this.order.appendChild(ui.option("desc", "Z to A"));
      this.order.addEventListener("change", function () { self.renderList(); });
      this.narrowing = el("div", "library-sidebar-narrowing");
      this.narrowing.appendChild(this.category); this.narrowing.appendChild(this.order);
      this.count = el("small", "muted");
      this.list = el("div", "library-sidebar-list");
      this.content.appendChild(this.search);
      this.content.appendChild(this.narrowing);
      this.content.appendChild(this.count);
      this.content.appendChild(this.list);
      this.root.appendChild(this.toggleButton);
      this.root.appendChild(this.content);
      if (!options.localOnly && options.session && options.send && this.adapter.wireKind) {
        this.store = new Store(options.session, options.send, this.adapter.wireKind, this.changed);
        this.copy = new Copy(options.session, options.send, this.adapter, function (outcome) {
          if (outcome && outcome.status === "completed" && self.store.page) {
            self.store.read(0, self.store.page.generation);
          }
          self.changed();
        });
        this.setup = new Setup(options.session, options.send, this.changed);
        this.root.appendChild(this.copy.root); this.root.appendChild(this.setup.root);
      }
      this.more = ui.button("Load more", function () { self.store.more(); });
      this.content.appendChild(this.more);
      this.drag = new Drag(this);
      this.paint();
    }
    Sidebar.prototype.paint = function () {
      this.content.hidden = this.collapsed;
      this.root.classList.toggle("is-collapsed", this.collapsed);
      this.toggleButton.setAttribute("aria-expanded", String(!this.collapsed));
    };
    Sidebar.prototype.toggle = function () {
      if (this.disposed) return;
      this.closeDetails();
      this.collapsed = !this.collapsed;
      this.paint();
    };
    Sidebar.prototype.refresh = function (state, context, enabled) {
      if (this.disposed) return;
      this.state = state;
      this.context = context;
      this.enabled = Boolean(enabled);
      if (this.store) {
        this.store.update(state);
        var held = this.copy.held;
        this.copy.refresh(state, this.enabled && this.store.available &&
          (!held || this.store.valid(held.row.library)));
        this.setup.refresh(state);
      }
      this.updateRows();
      var live = this.records.map(function (row) { return row.id; }), self = this;
      Object.keys(this.entries).forEach(function (id) {
        if (live.indexOf(id) !== -1) return;
        if (self.detail === self.entries[id]) self.closeDetails();
        delete self.entries[id];
      });
      this.renderList();
      if (this.detail) this.renderDetails();
      this.paintActions();
      if (!this.enabled) this.drag.end();
    };
    Sidebar.prototype.use = function (row, selection) {
      if (this.disposed || !this.enabled || this.busy() || !this.records.some(function (live) {
        return live.id === row.id;
      })) return false;
      var target = this.adapter.target(Object.assign({}, this.context, selection ? { selection: selection } : {}));
      if (target.hint) return false;
      if (row.library) return this.copy.use(row, this.adapter.assignment ? this.adapter.assignment(this.context,
        target.params) : target.params);
      return this.onUse ? this.onUse(row, target.params) : false;
    };
    Sidebar.prototype.reveal = function (id) {
      if (this.disposed) return;
      this.collapsed = false;
      this.paint();
      if (!id) { this.search.focus(); return; }
      this.search.value = "";
      // Nothing that narrows the list may hide the record asked for: not a category, not a folded group.
      this.category.value = "";
      this.expanded = Object.create(null);
      var row = this.records.filter(function (candidate) { return candidate.id === id; })[0];
      if (row) this.expanded[this.adapter.category(row)] = true;
      this.renderList();
      this.openDetails(this.entries[id]);
    };
    /* Shows a record just made in this file: its source selected, and its details open as Reveal opens them. */
    Sidebar.prototype.revealLocal = function (id) {
      if (this.disposed) return;
      if (this.store && this.store.selected) { this.closeDetails(); this.store.select(""); this.updateRows(); }
      this.reveal(id);
    };
    Sidebar.prototype.dispose = function () {
      this.disposed = true;
      this.enabled = false;
      this.drag.end();
      this.closeDetails();
      if (this.store) { this.store.dispose(); this.copy.dispose(); this.setup.dispose(); }
    };
    Sidebar.prototype.busy = function () {
      return this.ownerBusy() || Boolean(this.copy && this.copy.busy()) || Boolean(this.store && this.store.busy());
    };
    Sidebar.prototype.guard = function () {
      if (this.copy && (this.copy.busy() || !this.copy.root.hidden)) return "Finish or cancel the library review.";
      if (this.setup && !this.setup.root.hidden) return "Close library setup before leaving.";
      return null;
    };
    Sidebar.prototype.updateRows = function () {
      this.records = this.store && this.store.selected ? this.store.rows : this.adapter.read(this.state);
      this.source.replaceChildren(el("option", "", "In this file")); this.source.children[0].value = "";
      if (this.store) this.store.providers.forEach(function (provider) {
        var option = el("option", "", provider.label); option.value = provider.id; this.source.appendChild(option);
      }, this);
      this.source.value = this.store ? this.store.selected : "";
      this.source.disabled = !this.store || !this.store.available || this.busy() || Boolean(this.guard());
      this.refreshButton.hidden = !this.store || !this.store.selected;
      this.refreshButton.disabled = this.busy() || Boolean(this.store && this.store.busy());
      this.setupButton.disabled = !this.setup || !this.setup.enabled || this.busy();
      if (this.createButton) this.createButton.disabled = !this.enabled || this.busy();
      // Before any library is set up, the button says what the user came to do.
      this.setupButton.textContent = this.store && this.store.providers.length ? "Library setup…" :
        "Add a library…";
      this.more.hidden = !this.store || !this.store.page || !this.store.page.next_cursor;
      this.more.disabled = this.busy() || Boolean(this.store && this.store.busy());
      var page = this.store && this.store.selected && this.store.page;
      var status = this.store && this.store.selected && this.store.busy() ? "Loading library…" : "";
      if (this.store && this.store.error) status = this.store.error;
      // A hosted library's load runs after the request returns: `loading` until its answer arrives.
      if (page && page.state === "loading") status = "Loading library…";
      if (page && page.state === "cancelled") status = "Loading was cancelled." +
        (page.generation ? " Showing the last catalog." : "");
      if (page && (page.state === "failed" || page.state === "stale" || page.state === "unavailable")) {
        status = (page.failure && page.failure.message || "Library refresh failed.") +
          (page.generation ? " Showing the last successful catalog, loaded " + Math.floor(page.age_seconds || 0) +
            " seconds ago." : " No catalog is available.");
      }
      if (page && (page.unavailable || []).length) status += " Some record kinds or libraries are unavailable.";
      var notes = page && page.warnings || [];
      var skipped = notes.filter(function (note) { return SKIPPED[note.code] && note.record_id; });
      var other = notes.filter(function (note) { return skipped.indexOf(note) < 0; });
      if (other.some(function (note) { return KEPT[note.code]; })) status += " Some library records were normalized.";
      if (other.some(function (note) { return !KEPT[note.code]; })) {
        status += " Some library records or files were skipped.";
      }
      if (skipped.length) status += " " + skipped.length + (skipped.length === 1 ? " record was" : " records were") +
        " not loaded:";
      this.sourceStatus.textContent = status;
      this.renderSkipped(skipped);
      this.renderList();
    };
    // Each row left out, by record ID (its name may be what was missing) and the reason in PH-Composer's words.
    Sidebar.prototype.renderSkipped = function (skipped) {
      this.skipped.replaceChildren();
      skipped.slice(0, SKIPPED_SHOWN).forEach(function (note) {
        this.skipped.appendChild(el("li", "", "Record " + note.record_id + ": " + SKIPPED[note.code] + "."));
      }, this);
      if (skipped.length > SKIPPED_SHOWN) {
        this.skipped.appendChild(el("li", "muted", "And " + (skipped.length - SKIPPED_SHOWN) + " more."));
      }
      this.skipped.hidden = !skipped.length;
    };
    Sidebar.prototype.add = function (row) {
      if (this.disposed || !this.enabled || this.busy() || !this.copy || !this.records.some(function (live) {
        return live.id === row.id;
      })) return false;
      return this.copy.use(row);
    };
    Object.assign(Sidebar.prototype, rows);
    return Sidebar;
  });
