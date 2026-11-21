/* The library Programs the Zones / Programs view offers on a Zone: each added library source's `programs` catalog,
   read through the library's own stores (library/store.js), with its `schedules` catalog loaded beside it, since
   copying a Program copies the Schedules it names from the same source and refuses `library.dependency_missing`
   while that catalog was never loaded (context/CONTRACTS.md, "Library dependencies").

   Nothing loads until the view is first shown; then each source loads once, and every later page of its rows is
   read as the store reports a cursor. A source with no Programs, or one whose load failed, offers none. Choosing a
   row is the view's: `copy(row)` gives the parameters `ph_composer.programs.assign_library_program` takes, or null
   with the reason when the row's local copy must be reviewed first. */
PhComposerUI.define("features/programs/library_programs", ["snapshot", "library/store"], function (snapshot, Store) {
  "use strict";
  var SECTION = "ph_composer.library.provider_catalogs";
  var KIND = "programs", DEPENDENCY = "schedules";
  var REVIEW = "This library Program has a local copy that differs from it. Review it on the Programs tab, " +
    "then choose the local copy here.";

  function LibraryPrograms(session, send, changed) {
    this.session = session; this.send = send; this.changed = changed;
    this.sources = Object.create(null); this.order = [];
  }

  /* Each snapshot: the sources the library publishes and each store's outcomes. */
  LibraryPrograms.prototype.consume = function (state) {
    var self = this, providers = snapshot.value(state, SECTION) || [];
    var live = providers.filter(function (provider) { return (provider.kinds || []).indexOf(KIND) >= 0; });
    this.order = live.map(function (provider) { return provider.id; });
    Object.keys(this.sources).forEach(function (id) {
      if (self.order.indexOf(id) >= 0) return;
      self.sources[id].programs.dispose(); self.sources[id].schedules.dispose(); delete self.sources[id];
    });
    live.forEach(function (provider) {
      var source = self.sources[provider.id];
      if (!source) {
        source = self.sources[provider.id] = { id: provider.id,
          programs: new Store(self.session, self.send, KIND, self.changed),
          schedules: new Store(self.session, self.send, DEPENDENCY, self.changed), started: false };
      }
      source.label = provider.label;
      source.programs.update(state); source.schedules.update(state);
      if (source.started) source.programs.more();
    });
  };

  /* Whether every source has started its loads. */
  LibraryPrograms.prototype.started = function () {
    var self = this;
    return this.order.every(function (id) { return self.sources[id].started; });
  };

  /* Once the view shows: each source not yet read loads its Schedules and Programs, once. */
  LibraryPrograms.prototype.start = function () {
    var self = this;
    this.order.forEach(function (id) {
      var source = self.sources[id];
      if (source.started) return;
      source.started = true;
      source.schedules.select(id); source.programs.select(id);
    });
  };

  /* Each source with the rows it offers: Programs not yet in this file (a reused one is listed with this file's
     own), by label. */
  LibraryPrograms.prototype.groups = function () {
    var self = this;
    return this.order.map(function (id) {
      var source = self.sources[id];
      var rows = (source.programs.rows || []).filter(function (row) {
        return row.resolution && row.resolution.outcome !== "reuse";
      }).sort(function (a, b) { return String(a.display_label).localeCompare(String(b.display_label)); });
      return { id: id, label: source.label, rows: rows };
    }).filter(function (group) { return group.rows.length; });
  };

  LibraryPrograms.prototype.find = function (rowId) {
    var found = null;
    this.groups().some(function (group) {
      found = group.rows.filter(function (row) { return row.id === rowId; })[0] || null;
      return Boolean(found);
    });
    return found;
  };

  /* The copy a chosen row makes: `{ params }`, or `{ reason }` when its local copy must be reviewed first. */
  LibraryPrograms.prototype.copy = function (row) {
    var outcome = row.resolution && row.resolution.outcome, library = row.library;
    if (outcome !== "create") return { reason: REVIEW };
    var source = this.sources[library.provider_id];
    if (source && source.schedules.loading()) return { reason: "The library's Schedules are still loading." };
    return { params: { provider_id: library.provider_id, kind: KIND, generation: library.generation,
      library_id: library.library_id, record_id: library.record_id, choice: "create" } };
  };

  LibraryPrograms.prototype.busy = function () {
    var self = this;
    return this.order.some(function (id) {
      return self.sources[id].programs.busy() || self.sources[id].schedules.busy();
    });
  };

  LibraryPrograms.prototype.dispose = function () {
    var self = this;
    Object.keys(this.sources).forEach(function (id) {
      self.sources[id].programs.dispose(); self.sources[id].schedules.dispose();
    });
    this.sources = Object.create(null); this.order = [];
  };

  return LibraryPrograms;
});
