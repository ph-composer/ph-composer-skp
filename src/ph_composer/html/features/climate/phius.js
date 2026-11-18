/* The Phius climate data pane: one of three empty states while the Model holds no climate, from the climate data
   folders on this computer (`folders.list`, read each time the pane is shown and after the climate data dialog
   closes) and the Model's site (J3), or the attached pane (attached.js) once it holds one.
     no folder   says so, says why PH-Composer ships none, and offers Choose Climate Data Folder (board 2);
     no site     asks for the site first and offers Set Location (board 9);
     ready       names the dataset the station picker opens on, with its station count (board 10).
   Each offers Enter Values by Hand, which opens the values editor. Choose Station opens the station
   picker. The folders are read with a climate attached too: Replace explains instead of opening when none
   is found. */
PhComposerUI.define("features/climate/phius", ["workspace", "request", "features/climate/shared",
  "features/climate/attached"],
function (ui, requests, shared, Attached) {
  "use strict";
  var el = ui.element, LIST = shared.PREFIX + "folders.list";
  var PAINT = { loading: "loading", unreadable: "noFolder", no_folder: "noFolder", no_site: "noSite",
    ready: "ready", attached: "showAttached" };

  /* `actions.openData(add)` opens Climate Data on This Computer, starting Add Folder when `add`;
     `actions.setLocation()` opens Set Location; `actions.choose(preselect)` opens the station picker;
     `actions.replace(trigger)` is the attached pane's Replace; `actions.values(values)` opens the
     values editor, on a climate's values for Edit Values or empty with none. */
  function Pane(session, send, actions) {
    this.actions = actions; this.folders = undefined; this.failure = null; this.shown = false; this.painted = null;
    this.reads = requests.channel(session, send, "climate_phius_folders", "query.invoke");
    this.root = el("section", "climate-pane climate-phius");
    this.attached = new Attached(session, send, { replace: actions.replace, openData: actions.openData,
      setLocation: actions.setLocation, editValues: actions.values,
      update: function (source) {
        actions.choose({ folder_id: source.folder_id, station_key: source.station_key });
      } });
  }

  /* Reads the folders again the next time the pane is shown, or now if it is. What was read before is not shown
     meanwhile: the dialog may have changed it. */
  Pane.prototype.refresh = function () {
    this.stale = true; this.outdated = true;
    this.attached.refreshSource();
    if (this.shown) this.read();
  };

  Pane.prototype.read = function () {
    this.stale = false;
    if (!this.reads.busy()) this.reads.run(LIST, {}); else this.stale = true;
  };

  Pane.prototype.render = function (state, summary, site, shown) {
    var listed = this.reads.consume(state);
    if (listed) {
      this.folders = listed.status === "completed" ? listed.value : null;
      this.failure = listed.status === "completed" ? null : listed.message;
      if (this.stale) this.read(); else this.outdated = false;
    }
    var opened = shown && !this.shown;
    this.shown = shown;
    var attached = Boolean(summary && summary.climate.state !== "none");
    if (shown && (opened || this.stale || this.folders === undefined)) this.read();
    if (summary && !attached) this.attached.forget();
    this.attached.setSite(site);
    var waiting = this.folders === undefined || this.outdated;
    // With a climate attached the folders only decide Replace, so the pane does not wait for them.
    this.attached.render(state, shown && attached, summary && summary.design_temperatures.state,
      waiting ? undefined : this.failure ? { failure: this.failure } : this.folders);
    var view = attached ? "attached" : !summary || !site || waiting ? "loading" :
      this.failure ? "unreadable" : this.stateFor(site);
    this.siteSet = Boolean(site && site.state === "set");
    var key = view + "|" + this.siteSet + JSON.stringify(this.folders || null) + (this.failure || "");
    if (key === this.painted) return;
    this.painted = key;
    this.root.setAttribute("data-state", view);
    this[PAINT[view]](summary);
  };

  /* Whether Replace should explain rather than open: the folders are read and none is found now. */
  Pane.prototype.noFolder = function () { return this.attached.noFolder(); };

  /* A folder that cannot be found now is not one the picker can read: with none found, the pane is empty. */
  Pane.prototype.found = function () {
    return ((this.folders && this.folders.folders) || []).filter(function (folder) { return folder.found; });
  };

  Pane.prototype.stateFor = function (site) {
    if (!this.found().length) return "no_folder";
    return site.state === "set" ? "ready" : "no_site";
  };

  Pane.prototype.box = function (title, intro, bullets, buttons) {
    var box = el("div", "climate-empty"), list = el("ul"), row = el("div", "climate-empty-actions");
    box.appendChild(el("h2", "", title));
    if (intro) box.appendChild(el("p", "", intro));
    (bullets || []).forEach(function (line) { list.appendChild(el("li", "", line)); });
    if (bullets && bullets.length) box.appendChild(list);
    buttons.forEach(function (button) { row.appendChild(button); });
    box.appendChild(row);
    this.root.replaceChildren(box);
  };

  Pane.prototype.primary = function (label, run) {
    var button = ui.button(label, run); button.className = "primary"; return button;
  };

  Pane.prototype.hand = function () {
    var self = this;
    return ui.button("Enter Values by Hand…", function () { self.actions.values(null); });
  };

  Pane.prototype.noFolder = function () {
    var self = this, missing = (this.folders && this.folders.folders || []).length > 0;
    if (this.failure) {
      return this.box("No Phius climate data on this computer", this.failure, [], [this.hand()]);
    }
    if (missing) {
      return this.box("The climate data folder cannot be found", "The climate data folder set up on this " +
        "computer is not where it was. It may have moved, or be on a drive that is not connected.",
        ["Locate it, or choose another, in Climate Data on This Computer."],
        [this.primary("Climate Data on This Computer…", function () { self.actions.openData(false); }),
          this.hand()]);
    }
    this.box("No Phius climate data on this computer", "PH-Composer does not include climate data. Phius " +
      "licenses its climate files to you, so they stay on your computer.",
      ["Choose the folder that holds your Phius station files. Subfolders are read too.",
        "The folder's location is remembered on this computer only.",
        "When you pick a station, its values are copied into this Model. The Model then reads without the folder.",
        "With no climate files, type or paste the monthly values and peak loads yourself."],
      [this.primary("Choose Climate Data Folder…", function () { self.actions.openData(true); }),
        this.hand()]);
  };

  Pane.prototype.noSite = function () {
    var self = this;
    this.box("Set the site location first", "A station is checked against the site: Phius allows one within " +
      "50 miles (80 km) and 400 feet (122 m) of elevation. The station list is sorted by distance from the site.",
      [], [this.primary("Set Location…", function () { self.actions.setLocation(); }),
        this.hand()]);
  };

  Pane.prototype.ready = function () {
    var self = this, dataset = shared.openingDataset(this.folders), stations = dataset.station_count;
    this.box("No Phius climate data in this Model", dataset.name + " · " + Number(stations).toLocaleString("en-US") +
      " station" + (stations === 1 ? "" : "s") + " on this computer.",
      ["Choose a station near the site. Its values are copied into this Model, which then reads without the folder.",
        "With a custom dataset from Phius, or no station file, type or paste the monthly values and peak loads " +
        "yourself."],
      [this.primary("Choose Station…", function () { self.actions.choose(); }), this.hand()]);
  };

  Pane.prototype.showAttached = function () { this.root.replaceChildren(this.attached.root); };

  Pane.prototype.loading = function () {
    this.root.replaceChildren(el("p", "muted", "Reading the climate data folders…"));
  };

  Pane.prototype.dispose = function () { this.reads.reset(); this.attached.dispose(); };

  return Pane;
});
