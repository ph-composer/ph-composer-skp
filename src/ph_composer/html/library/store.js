/* One placement's provider pages. Public labels and immutable generations never carry transport addresses. */
PhComposerUI.define("library/store", ["request", "snapshot"], function (request, snapshot) {
  "use strict";
  var PREFIX = "ph_composer.library", SECTION = PREFIX + ".provider_catalogs";
  function Store(session, send, kind, changed) {
    this.session = session; this.kind = kind; this.changed = changed;
    this.loaded = Object.create(null);
    this.providers = []; this.selected = ""; this.rows = []; this.page = null; this.available = false;
    this.views = request.channel(session, send, "library-load", "setup.invoke");
    this.queries = request.channel(session, send, "library-page", "query.invoke");
    this.cancels = request.channel(session, send, "library-cancel", "setup.invoke");
  }
  Store.prototype.busy = function () { return this.views.busy() || this.queries.busy(); };
  /* A load or Refresh request is out; the page it will replace is still held. */
  Store.prototype.reloading = function () { return this.views.busy(); };
  Store.prototype.provider = function () {
    var selected = this.selected;
    return this.providers.filter(function (row) { return row.id === selected; })[0];
  };
  Store.prototype.catalog = function (provider) {
    var kind = this.kind;
    return provider && (provider.catalogs || []).filter(function (row) { return row.kind === kind; })[0];
  };
  Store.prototype.valid = function (library) {
    if (!this.available || !library || library.kind !== this.kind) return false;
    return this.providers.some(function (provider) {
      var catalog = this.catalog(provider);
      return provider.id === library.provider_id && catalog && catalog.generation === library.generation;
    }, this);
  };
  Store.prototype.reset = function () {
    this.views.reset(); this.queries.reset(); this.cancels.reset(); this.rows = []; this.page = null;
    this.pageRevision = null; this.attempted = null; this.error = "";
  };
  Store.prototype.update = function (state) {
    if (this.disposed) return;
    var providers = state.session === this.session && snapshot.value(state, SECTION);
    this.available = Boolean(providers);
    this.providers = (providers || []).filter(function (row) { return row.kinds.includes(this.kind); }, this);
    if (!this.available || (this.selected && !this.provider())) {
      this.reset(); this.loaded = Object.create(null); this.selected = ""; return;
    }
    this.revision = state.revision;
    this.views.consume(state); this.queries.consume(state); this.cancels.consume(state);
    Object.keys(this.loaded).forEach(function (id) {
      var provider = this.providers.filter(function (row) { return row.id === id; })[0];
      var catalog = this.catalog(provider), cache = this.loaded[id];
      if (!catalog || catalog.generation !== cache.generation || cache.revision !== state.revision) {
        delete this.loaded[id];
      }
    }, this);
    var current = this.catalog(this.provider());
    /* A hosted library that disconnected dropped the generation the snapshot last named: its rows go too,
       never shown as current. */
    if (current && !current.generation && this.shownGeneration && this.page) {
      this.page = Object.assign({}, current); this.rows = []; this.attempted = null;
    }
    this.shownGeneration = current ? current.generation : null;
    if (current && current.generation && !this.busy() &&
      this.attempted !== current.generation + ":" + state.revision &&
      (!this.page || this.page.generation !== current.generation || this.pageRevision !== state.revision)) {
      this.read(null, current.generation);
    } else if (current && this.page && current.generation === this.page.generation) {
      this.page = Object.assign({}, this.page, current);
    }
  };
  Store.prototype.select = function (id) {
    if (this.disposed || !this.available) return false;
    if (id && !this.providers.some(function (row) { return row.id === id; })) return false;
    this.reset(); this.selected = id;
    var provider = this.provider();
    if (!provider) return true;
    var catalog = this.catalog(provider);
    if (catalog && catalog.generation) this.read(null, catalog.generation);
    // A hosted load already running is followed, not started again.
    else if (catalog && catalog.state === "loading") this.page = Object.assign({}, catalog);
    else this.load();
    this.changed(); return true;
  };
  Store.prototype.load = function () {
    if (this.disposed || !this.provider() || this.busy()) return false;
    var self = this;
    this.error = "";
    this.views.run(PREFIX + ".load", { provider_id: this.selected, kind: this.kind }, {
      onDone: function (outcome) {
        self.page = outcome.value;
        if (outcome.value.generation) self.read(null, outcome.value.generation);
        self.changed();
      }, onFail: function (outcome) { self.error = outcome.message; self.changed(); } });
    this.changed(); return true;
  };
  /* A null cursor reads the first page. A later page is bound to the generation and revision the first
     was read at; when either moved, the host refuses the cursor and the read starts again. */
  Store.prototype.read = function (cursor, generation) {
    if (this.disposed || !this.provider() || this.queries.busy()) return false;
    var self = this, provider = this.selected, params = { provider_id: provider, kind: this.kind,
      generation: generation, limit: 100 };
    if (cursor) params.cursor = cursor;
    this.attempted = generation + ":" + this.revision;
    this.queries.run(PREFIX + ".in_file", params, {
      onDone: function (outcome) {
        var page = outcome.value, revision = outcome.revision === undefined ? self.revision : outcome.revision;
        if (!cursor || !self.page || self.page.generation !== page.generation) self.rows = [];
        self.rows = self.rows.concat(page.rows.map(function (row) {
          return { id: JSON.stringify([provider, self.kind, row.library_id, row.record_id]),
            values: row.snapshot, display_label: row.display_label, resolution: row.resolution,
            library: Object.assign({ provider_id: provider, kind: self.kind, generation: page.generation }, row) };
        }));
        self.loaded[provider] = { rows: self.rows.slice(), generation: page.generation, revision: revision };
        self.page = page; self.pageRevision = revision; self.error = ""; self.changed();
      }, onFail: function (outcome) {
        if (cursor && outcome.code === "query.cursor_expired") { self.read(null, generation); return; }
        /* A reload replaced the generation: the next snapshot names the new one and reads it from the start. */
        if (cursor && outcome.code === "library.catalog_stale") {
          self.rows = []; self.page = null; self.changed(); return;
        }
        self.error = outcome.message; self.changed();
      } });
    return true;
  };
  Store.prototype.localInfo = function (record) {
    var source = record.values.source, self = this;
    if (!source || source.kind !== "library" || source.record_kind !== this.kind) return null;
    var found;
    Object.keys(this.loaded).some(function (id) {
      var provider = self.providers.filter(function (row) { return row.id === id; })[0];
      if (!provider || provider.provider_kind !== source.provider_kind) return false;
      return self.loaded[id].rows.some(function (row) {
        if (row.library.library_id !== source.library_id || row.library.record_id !== source.record_id) return false;
        var candidate = row.resolution.candidates.filter(function (one) { return one.id === record.id; })[0];
        if (!candidate) return false;
        found = { row: row, label: provider.label, changed: Boolean(candidate.source_changed),
          comparisonAvailable: Boolean(candidate.comparison_available) }; return true;
      });
    });
    return found || { label: source.library_id, changed: false, comparisonAvailable: false };
  };
  /* A hosted library's load runs after its request returned: its catalog reads `loading` until it ends. The
     page keeps that state until the first page of what it published is read, or that read fails. */
  Store.prototype.catalogLoading = function (providerId) {
    var catalog = this.catalog(this.providers.filter(function (row) { return row.id === providerId; })[0]);
    return Boolean(catalog && catalog.state === "loading");
  };
  Store.prototype.cancellable = function () { return Boolean(this.selected) && this.catalogLoading(this.selected); };
  Store.prototype.loading = function () {
    return this.cancellable() || Boolean(!this.error && this.page && this.page.state === "loading");
  };
  Store.prototype.cancelling = function () { return this.cancels.busy(); };
  /* Stops that load; the catalog it would have replaced stays. The next snapshot says `cancelled`. */
  Store.prototype.cancel = function () {
    if (this.disposed || !this.cancellable() || this.cancels.busy()) return false;
    var self = this;
    this.cancels.run(PREFIX + ".cancel_load", { provider_id: this.selected, kind: this.kind }, {
      onDone: function () { self.changed(); },
      onFail: function (outcome) { self.error = outcome.message; self.changed(); } });
    this.changed(); return true;
  };
  Store.prototype.refresh = function () { return this.load(); };
  Store.prototype.more = function () {
    return this.page && Boolean(this.page.next_cursor) && !this.busy() &&
      this.read(this.page.next_cursor, this.page.generation);
  };
  Store.prototype.dispose = function () { this.disposed = true; this.available = false; this.reset(); };
  return Store;
});
